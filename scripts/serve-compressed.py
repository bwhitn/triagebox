#!/usr/bin/env python3
"""Static server with optional forced gzip content-encoding for selected extensions."""

from __future__ import annotations

import argparse
import gzip
import json
import os
import posixpath
import re
import shutil
import subprocess
import tempfile
from urllib.parse import parse_qs, urlsplit
from functools import partial
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from typing import Set


def parse_ext_list(raw: str) -> Set[str]:
    exts: Set[str] = set()
    for part in raw.split(","):
        part = part.strip().lower()
        if not part:
            continue
        if not part.startswith("."):
            part = "." + part
        exts.add(part)
    return exts


def env_int(name: str, default: int) -> int:
    raw = os.environ.get(name, str(default)).strip()
    try:
        value = int(raw)
    except ValueError as exc:
        raise SystemExit(f"{name} must be an integer (got: {raw})") from exc
    return value


COMPRESS_EXT = parse_ext_list(
    os.environ.get(
        "COMPRESS_EXT",
        ".html,.htm,.css,.js,.mjs,.json,.txt,.svg,.wasm,.img,.bin,.map",
    )
)
COMPRESS_MIN_BYTES = env_int("COMPRESS_MIN_BYTES", 1024)
COMPRESS_LEVEL = env_int("COMPRESS_LEVEL", 6)
DISK_UPLOAD_MAX_BYTES = env_int("DISK_UPLOAD_MAX_BYTES", 8 * 1024 * 1024 * 1024)
DISK_UPLOAD_SUBDIR = os.environ.get("DISK_UPLOAD_SUBDIR", "uploads").strip("/") or "uploads"
DISK_UPLOAD_FILENAME = os.environ.get("DISK_UPLOAD_FILENAME", "custom-disk.img").strip() or "custom-disk.img"
DISK_BROWSE_MAX_ENTRIES = env_int("DISK_BROWSE_MAX_ENTRIES", 4096)
DISK_FILE_DOWNLOAD_MAX_BYTES = env_int("DISK_FILE_DOWNLOAD_MAX_BYTES", 2 * 1024 * 1024 * 1024)
DISK_FILE_UPLOAD_MAX_BYTES = env_int("DISK_FILE_UPLOAD_MAX_BYTES", 512 * 1024 * 1024)
DISK_IMPORT_ROOT = os.environ.get("DISK_IMPORT_ROOT", ".").strip() or "."
DEBUGFS_BIN = os.environ.get("DEBUGFS_BIN", shutil.which("debugfs") or "").strip()
DEBUGFS_LS_RE = re.compile(r"^/(\d+)/([0-7]{6})/(\d+)/(\d+)/(.*)/([^/]*)/$")


class CompressedStaticHandler(SimpleHTTPRequestHandler):
    server_version = "CompressedHTTP/1.0"

    def _request_path(self) -> str:
        return urlsplit(self.path).path

    def _request_query(self) -> dict[str, list[str]]:
        return parse_qs(urlsplit(self.path).query, keep_blank_values=True)

    def _uploads_dir(self) -> str:
        return os.path.join(self.directory, DISK_UPLOAD_SUBDIR)

    def _uploaded_disk_path(self) -> str:
        return os.path.join(self._uploads_dir(), DISK_UPLOAD_FILENAME)

    def _import_root_dir(self) -> str:
        return os.path.normpath(os.path.join(self.directory, DISK_IMPORT_ROOT))

    def _sanitize_filename(self, value: str) -> str:
        if not value:
            return "uploaded.img"
        base = os.path.basename(value.strip())
        cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", base).strip("._")
        return cleaned or "uploaded.img"

    def _normalize_disk_path(self, raw_path: str) -> str:
        value = (raw_path or "").strip()
        if not value:
            return "/"
        if any(ch in value for ch in ("\x00", "\n", "\r")):
            raise ValueError("invalid path")
        if not value.startswith("/"):
            value = "/" + value
        normalized = posixpath.normpath(value)
        if not normalized.startswith("/"):
            raise ValueError("invalid path")
        return normalized

    def _resolve_import_source(self, raw_src: str) -> str:
        value = (raw_src or "").strip()
        if not value:
            raise ValueError("missing src path")
        if any(ch in value for ch in ("\x00", "\n", "\r")):
            raise ValueError("invalid src path")
        normalized_rel = posixpath.normpath("/" + value).lstrip("/")
        if normalized_rel in {"", "."}:
            raise ValueError("invalid src path")
        import_root = os.path.realpath(self._import_root_dir())
        candidate = os.path.realpath(os.path.join(import_root, normalized_rel))
        if not (candidate == import_root or candidate.startswith(import_root + os.sep)):
            raise ValueError("src path escapes import root")
        return candidate

    def _debugfs_quote(self, raw: str) -> str:
        escaped = raw.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'

    def _run_debugfs(self, disk_path: str, command: str, *, writable: bool = False) -> str:
        if not DEBUGFS_BIN:
            raise RuntimeError("debugfs is not available on the server")
        argv = [DEBUGFS_BIN]
        if writable:
            argv.append("-w")
        argv.extend(["-R", command, disk_path])
        proc = subprocess.run(
            argv,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        combined = "\n".join(part for part in (proc.stdout, proc.stderr) if part)
        cleaned_lines = []
        for line in combined.splitlines():
            line = line.rstrip()
            if not line:
                continue
            if line.startswith("debugfs "):
                continue
            cleaned_lines.append(line)
        cleaned_text = "\n".join(cleaned_lines).strip()
        lower_text = cleaned_text.lower()
        fatal_markers = (
            "filesystem not open",
            "attempt to read block",
            "bad magic number",
            "while trying to open",
            "couldn't find valid filesystem superblock",
            "short read while trying to open",
            "filesystem opened read/only",
        )
        if any(marker in lower_text for marker in fatal_markers):
            raise RuntimeError(cleaned_text or "debugfs failed to open filesystem")
        if proc.returncode != 0:
            raise RuntimeError(cleaned_text or f"debugfs exited with code {proc.returncode}")
        return cleaned_text

    def _debugfs_type_from_mode(self, mode_raw: str) -> str:
        try:
            mode_value = int(mode_raw, 8)
        except ValueError:
            return "other"
        file_type = mode_value & 0o170000
        if file_type == 0o040000:
            return "dir"
        if file_type == 0o100000:
            return "regular"
        if file_type == 0o120000:
            return "symlink"
        return "other"

    def _debugfs_stat(self, disk_path: str, target_path: str) -> dict:
        output = self._run_debugfs(disk_path, f"stat {self._debugfs_quote(target_path)}")
        if "File not found by ext2_lookup" in output or "File not found" in output:
            raise FileNotFoundError(target_path)
        type_match = re.search(r"Type:\s+([A-Za-z_]+)", output)
        size_match = re.search(r"Size:\s+(\d+)", output)
        mode_match = re.search(r"Mode:\s+([0-7]{4,6})", output)
        if not type_match:
            raise RuntimeError("failed to inspect file type in uploaded disk")
        file_type = type_match.group(1).strip().lower()
        size = int(size_match.group(1)) if size_match else 0
        mode = mode_match.group(1) if mode_match else ""
        return {"type": file_type, "size": size, "mode": mode}

    def _debugfs_list_dir(self, disk_path: str, directory_path: str) -> list[dict]:
        output = self._run_debugfs(disk_path, f"ls -p {self._debugfs_quote(directory_path)}")
        if "File not found by ext2_lookup" in output or "File not found" in output:
            raise FileNotFoundError(directory_path)
        if "not a directory" in output.lower():
            raise NotADirectoryError(directory_path)

        entries: list[dict] = []
        for line in output.splitlines():
            line = line.strip()
            if not line.startswith("/"):
                continue
            match = DEBUGFS_LS_RE.match(line)
            if not match:
                continue
            inode_raw, mode_raw, _, _, name, size_raw = match.groups()
            if name in {".", ".."}:
                continue
            entry_type = self._debugfs_type_from_mode(mode_raw)
            size = int(size_raw) if size_raw.isdigit() else 0
            if directory_path == "/":
                full_path = "/" + name
            else:
                full_path = directory_path.rstrip("/") + "/" + name
            entries.append(
                {
                    "name": name,
                    "path": full_path,
                    "type": entry_type,
                    "size": size,
                    "mode": mode_raw,
                    "inode": int(inode_raw),
                }
            )

        entries.sort(key=lambda item: (item["type"] != "dir", item["name"].lower()))
        if len(entries) > DISK_BROWSE_MAX_ENTRIES:
            return entries[:DISK_BROWSE_MAX_ENTRIES]
        return entries

    def _send_json(self, status: int, payload: dict, send_body: bool = True) -> None:
        body = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    def _disk_payload(self, uploaded: bool, *, name: str = "", size: int = 0, mtime: int = 0) -> dict:
        payload = {"uploaded": uploaded}
        if uploaded:
            payload["name"] = name
            payload["size"] = size
            payload["mtime"] = mtime
            payload["url"] = f"/{DISK_UPLOAD_SUBDIR}/{DISK_UPLOAD_FILENAME}?v={mtime}"
        return payload

    def _handle_get_disk(self, send_body: bool = True) -> None:
        disk_path = self._uploaded_disk_path()
        if not os.path.isfile(disk_path):
            self._send_json(HTTPStatus.OK, self._disk_payload(False), send_body=send_body)
            return
        st = os.stat(disk_path)
        self._send_json(
            HTTPStatus.OK,
            self._disk_payload(
                True,
                name=os.path.basename(disk_path),
                size=st.st_size,
                mtime=int(st.st_mtime),
            ),
            send_body=send_body,
        )

    def _handle_delete_disk(self) -> None:
        disk_path = self._uploaded_disk_path()
        try:
            if os.path.exists(disk_path):
                os.remove(disk_path)
        except OSError as exc:
            self._send_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {"error": f"failed to remove uploaded disk: {exc}"},
            )
            return
        self._send_json(HTTPStatus.OK, self._disk_payload(False))

    def _handle_post_disk(self) -> None:
        transfer_encoding = self.headers.get("Transfer-Encoding", "").lower()
        is_chunked = "chunked" in transfer_encoding
        content_length = None

        if is_chunked:
            if DISK_UPLOAD_MAX_BYTES <= 0:
                max_upload_bytes = None
            else:
                max_upload_bytes = DISK_UPLOAD_MAX_BYTES
        else:
            content_length_raw = self.headers.get("Content-Length", "").strip()
            if not content_length_raw:
                self._send_json(
                    HTTPStatus.LENGTH_REQUIRED,
                    {"error": "Content-Length header is required (or use chunked transfer encoding)"},
                )
                return
            try:
                content_length = int(content_length_raw, 10)
            except ValueError:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid Content-Length header"})
                return
            if content_length <= 0:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "request body must be non-empty"})
                return
            if DISK_UPLOAD_MAX_BYTES > 0 and content_length > DISK_UPLOAD_MAX_BYTES:
                self._send_json(
                    HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                    {"error": f"disk upload exceeds max size ({DISK_UPLOAD_MAX_BYTES} bytes)"},
                )
                return
            max_upload_bytes = content_length

        uploads_dir = self._uploads_dir()
        os.makedirs(uploads_dir, exist_ok=True)

        target_path = self._uploaded_disk_path()
        fd, tmp_path = tempfile.mkstemp(prefix=".disk-upload-", suffix=".tmp", dir=uploads_dir)
        written_bytes = 0
        try:
            with os.fdopen(fd, "wb") as tmp_out:
                if is_chunked:
                    while True:
                        chunk_size_line = self.rfile.readline(64 * 1024)
                        if not chunk_size_line:
                            raise OSError("chunked request ended unexpectedly")
                        chunk_size_raw = chunk_size_line.strip().split(b";", 1)[0]
                        try:
                            chunk_size = int(chunk_size_raw, 16)
                        except ValueError as exc:
                            raise OSError("invalid chunk size in request body") from exc
                        if chunk_size < 0:
                            raise OSError("invalid negative chunk size in request body")
                        if chunk_size == 0:
                            # consume trailer headers
                            while True:
                                trailer = self.rfile.readline(64 * 1024)
                                if trailer in (b"\r\n", b"\n", b""):
                                    break
                            break

                        if max_upload_bytes is not None and (written_bytes + chunk_size) > max_upload_bytes:
                            raise ValueError(f"disk upload exceeds max size ({DISK_UPLOAD_MAX_BYTES} bytes)")

                        remaining = chunk_size
                        while remaining > 0:
                            chunk = self.rfile.read(min(1024 * 1024, remaining))
                            if not chunk:
                                raise OSError("request body ended unexpectedly")
                            tmp_out.write(chunk)
                            remaining -= len(chunk)
                            written_bytes += len(chunk)

                        trailing = self.rfile.read(2)
                        if trailing not in (b"\r\n", b"\n"):
                            raise OSError("malformed chunk delimiter in request body")
                else:
                    remaining = content_length
                    while remaining > 0:
                        chunk = self.rfile.read(min(1024 * 1024, remaining))
                        if not chunk:
                            raise OSError("request body ended unexpectedly")
                        tmp_out.write(chunk)
                        remaining -= len(chunk)
                        written_bytes += len(chunk)

                if written_bytes <= 0:
                    raise OSError("request body must be non-empty")
            os.replace(tmp_path, target_path)
        except ValueError as exc:
            try:
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)
            except OSError:
                pass
            self._send_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": str(exc)})
            return
        except OSError as exc:
            try:
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)
            except OSError:
                pass
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"failed to store uploaded disk: {exc}"})
            return

        if DEBUGFS_BIN:
            try:
                # Validate that the uploaded image is a readable ext filesystem image.
                self._run_debugfs(target_path, "stat /")
            except RuntimeError as exc:
                try:
                    os.remove(target_path)
                except OSError:
                    pass
                self._send_json(
                    HTTPStatus.BAD_REQUEST,
                    {"error": f"uploaded disk is not a supported ext filesystem image: {exc}"},
                )
                return

        st = os.stat(target_path)
        requested_name = self._sanitize_filename(self.headers.get("X-Filename", ""))
        self._send_json(
            HTTPStatus.OK,
            self._disk_payload(
                True,
                name=requested_name,
                size=st.st_size,
                mtime=int(st.st_mtime),
            ),
        )

    def _handle_get_disk_files(self, send_body: bool = True) -> None:
        disk_path = self._uploaded_disk_path()
        if not os.path.isfile(disk_path):
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "no uploaded disk image"}, send_body=send_body)
            return
        if not DEBUGFS_BIN:
            self._send_json(HTTPStatus.NOT_IMPLEMENTED, {"error": "debugfs not available"}, send_body=send_body)
            return

        query = self._request_query()
        requested_path = query.get("path", ["/"])[0]
        try:
            normalized_path = self._normalize_disk_path(requested_path)
        except ValueError:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid path"}, send_body=send_body)
            return

        try:
            entries = self._debugfs_list_dir(disk_path, normalized_path)
        except FileNotFoundError:
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "path not found in uploaded disk"}, send_body=send_body)
            return
        except NotADirectoryError:
            self._send_json(
                HTTPStatus.BAD_REQUEST,
                {"error": "path is not a directory in uploaded disk"},
                send_body=send_body,
            )
            return
        except RuntimeError as exc:
            self._send_json(
                HTTPStatus.BAD_REQUEST,
                {"error": f"failed to inspect uploaded disk: {exc}"},
                send_body=send_body,
            )
            return

        self._send_json(
            HTTPStatus.OK,
            {
                "uploaded": True,
                "path": normalized_path,
                "entries": entries,
                "max_entries": DISK_BROWSE_MAX_ENTRIES,
            },
            send_body=send_body,
        )

    def _handle_download_disk_file(self, send_body: bool = True) -> None:
        disk_path = self._uploaded_disk_path()
        if not os.path.isfile(disk_path):
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "no uploaded disk image"}, send_body=send_body)
            return
        if not DEBUGFS_BIN:
            self._send_json(HTTPStatus.NOT_IMPLEMENTED, {"error": "debugfs not available"}, send_body=send_body)
            return

        query = self._request_query()
        requested_path = query.get("path", [""])[0]
        try:
            normalized_path = self._normalize_disk_path(requested_path)
        except ValueError:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid path"}, send_body=send_body)
            return

        try:
            stat_info = self._debugfs_stat(disk_path, normalized_path)
        except FileNotFoundError:
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "path not found in uploaded disk"}, send_body=send_body)
            return
        except RuntimeError as exc:
            self._send_json(
                HTTPStatus.BAD_REQUEST,
                {"error": f"failed to inspect uploaded disk: {exc}"},
                send_body=send_body,
            )
            return

        if stat_info["type"] != "regular":
            self._send_json(
                HTTPStatus.BAD_REQUEST,
                {"error": "path is not a regular file"},
                send_body=send_body,
            )
            return

        file_size = int(stat_info.get("size", 0))
        if DISK_FILE_DOWNLOAD_MAX_BYTES > 0 and file_size > DISK_FILE_DOWNLOAD_MAX_BYTES:
            self._send_json(
                HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                {"error": f"file exceeds download limit ({DISK_FILE_DOWNLOAD_MAX_BYTES} bytes)"},
                send_body=send_body,
            )
            return

        download_name = self._sanitize_filename(os.path.basename(normalized_path)) or "disk-file.bin"
        if not send_body:
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", f'attachment; filename="{download_name}"')
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(file_size))
            self.end_headers()
            return

        os.makedirs(self._uploads_dir(), exist_ok=True)
        fd, tmp_path = tempfile.mkstemp(prefix=".disk-file-", suffix=".bin", dir=self._uploads_dir())
        os.close(fd)
        try:
            debugfs_command = f"dump {self._debugfs_quote(normalized_path)} {self._debugfs_quote(tmp_path)}"
            output = self._run_debugfs(disk_path, debugfs_command)
            if "File not found by ext2_lookup" in output or "File not found" in output:
                raise FileNotFoundError(normalized_path)
            if not os.path.isfile(tmp_path):
                raise RuntimeError("debugfs did not produce an output file")

            extracted_size = os.path.getsize(tmp_path)
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", f'attachment; filename="{download_name}"')
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(extracted_size))
            self.end_headers()

            with open(tmp_path, "rb") as extracted_file:
                shutil.copyfileobj(extracted_file, self.wfile, length=64 * 1024)
        except FileNotFoundError:
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "path not found in uploaded disk"})
        except RuntimeError as exc:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"failed to extract file: {exc}"})
        finally:
            try:
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)
            except OSError:
                pass

    def _handle_put_disk_file(self) -> None:
        disk_path = self._uploaded_disk_path()
        if not os.path.isfile(disk_path):
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "no uploaded disk image"})
            return
        if not DEBUGFS_BIN:
            self._send_json(HTTPStatus.NOT_IMPLEMENTED, {"error": "debugfs not available"})
            return

        query = self._request_query()
        requested_name = self._sanitize_filename(self.headers.get("X-Filename", ""))
        requested_path = query.get("path", [""])[0]
        if requested_path.strip():
            try:
                normalized_path = self._normalize_disk_path(requested_path)
            except ValueError:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid path"})
                return
            if normalized_path == "/":
                normalized_path = "/" + requested_name
        else:
            normalized_path = "/" + requested_name

        transfer_encoding = self.headers.get("Transfer-Encoding", "").lower()
        is_chunked = "chunked" in transfer_encoding
        content_length = None
        if is_chunked:
            max_upload_bytes = DISK_FILE_UPLOAD_MAX_BYTES if DISK_FILE_UPLOAD_MAX_BYTES > 0 else None
        else:
            content_length_raw = self.headers.get("Content-Length", "").strip()
            if not content_length_raw:
                self._send_json(
                    HTTPStatus.LENGTH_REQUIRED,
                    {"error": "Content-Length header is required (or use chunked transfer encoding)"},
                )
                return
            try:
                content_length = int(content_length_raw, 10)
            except ValueError:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid Content-Length header"})
                return
            if content_length <= 0:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "request body must be non-empty"})
                return
            if DISK_FILE_UPLOAD_MAX_BYTES > 0 and content_length > DISK_FILE_UPLOAD_MAX_BYTES:
                self._send_json(
                    HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                    {"error": f"file upload exceeds max size ({DISK_FILE_UPLOAD_MAX_BYTES} bytes)"},
                )
                return
            max_upload_bytes = content_length

        os.makedirs(self._uploads_dir(), exist_ok=True)
        fd, tmp_path = tempfile.mkstemp(prefix=".disk-import-", suffix=".bin", dir=self._uploads_dir())
        written_bytes = 0
        try:
            with os.fdopen(fd, "wb") as tmp_out:
                if is_chunked:
                    while True:
                        chunk_size_line = self.rfile.readline(64 * 1024)
                        if not chunk_size_line:
                            raise OSError("chunked request ended unexpectedly")
                        chunk_size_raw = chunk_size_line.strip().split(b";", 1)[0]
                        try:
                            chunk_size = int(chunk_size_raw, 16)
                        except ValueError as exc:
                            raise OSError("invalid chunk size in request body") from exc
                        if chunk_size < 0:
                            raise OSError("invalid negative chunk size in request body")
                        if chunk_size == 0:
                            while True:
                                trailer = self.rfile.readline(64 * 1024)
                                if trailer in (b"\r\n", b"\n", b""):
                                    break
                            break

                        if max_upload_bytes is not None and (written_bytes + chunk_size) > max_upload_bytes:
                            raise ValueError(f"file upload exceeds max size ({DISK_FILE_UPLOAD_MAX_BYTES} bytes)")

                        remaining = chunk_size
                        while remaining > 0:
                            chunk = self.rfile.read(min(1024 * 1024, remaining))
                            if not chunk:
                                raise OSError("request body ended unexpectedly")
                            tmp_out.write(chunk)
                            remaining -= len(chunk)
                            written_bytes += len(chunk)

                        trailing = self.rfile.read(2)
                        if trailing not in (b"\r\n", b"\n"):
                            raise OSError("malformed chunk delimiter in request body")
                else:
                    remaining = content_length
                    while remaining > 0:
                        chunk = self.rfile.read(min(1024 * 1024, remaining))
                        if not chunk:
                            raise OSError("request body ended unexpectedly")
                        tmp_out.write(chunk)
                        remaining -= len(chunk)
                        written_bytes += len(chunk)

                if written_bytes <= 0:
                    raise OSError("request body must be non-empty")

            # Replace file if already present (ignore errors if it does not exist).
            try:
                self._run_debugfs(disk_path, f"rm {self._debugfs_quote(normalized_path)}", writable=True)
            except RuntimeError:
                pass

            self._run_debugfs(
                disk_path,
                f"write {self._debugfs_quote(tmp_path)} {self._debugfs_quote(normalized_path)}",
                writable=True,
            )

            self._send_json(
                HTTPStatus.OK,
                {
                    "uploaded": True,
                    "path": normalized_path,
                    "name": requested_name,
                    "size": written_bytes,
                },
            )
        except ValueError as exc:
            self._send_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": str(exc)})
        except RuntimeError as exc:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"failed to write file into disk: {exc}"})
        except OSError as exc:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"failed to read upload body: {exc}"})
        finally:
            try:
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)
            except OSError:
                pass

    def _handle_import_disk_file(self) -> None:
        disk_path = self._uploaded_disk_path()
        if not os.path.isfile(disk_path):
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "no uploaded disk image"})
            return
        if not DEBUGFS_BIN:
            self._send_json(HTTPStatus.NOT_IMPLEMENTED, {"error": "debugfs not available"})
            return

        query = self._request_query()
        src_raw = query.get("src", [""])[0]
        dest_raw = query.get("path", [""])[0]

        try:
            src_path = self._resolve_import_source(src_raw)
        except ValueError as exc:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if not os.path.isfile(src_path):
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "source file not found on server"})
            return

        file_size = os.path.getsize(src_path)
        if DISK_FILE_UPLOAD_MAX_BYTES > 0 and file_size > DISK_FILE_UPLOAD_MAX_BYTES:
            self._send_json(
                HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                {"error": f"source file exceeds size limit ({DISK_FILE_UPLOAD_MAX_BYTES} bytes)"},
            )
            return

        if dest_raw.strip():
            try:
                dest_path = self._normalize_disk_path(dest_raw)
            except ValueError:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid destination path"})
                return
            if dest_path == "/":
                dest_path = "/" + os.path.basename(src_path)
        else:
            dest_path = "/" + os.path.basename(src_path)

        try:
            # Replace existing file if it already exists.
            try:
                self._run_debugfs(disk_path, f"rm {self._debugfs_quote(dest_path)}", writable=True)
            except RuntimeError:
                pass
            self._run_debugfs(
                disk_path,
                f"write {self._debugfs_quote(src_path)} {self._debugfs_quote(dest_path)}",
                writable=True,
            )
        except RuntimeError as exc:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"failed to import file into disk: {exc}"})
            return

        self._send_json(
            HTTPStatus.OK,
            {
                "uploaded": True,
                "source": os.path.relpath(src_path, self._import_root_dir()),
                "path": dest_path,
                "size": file_size,
            },
        )

    def _parse_range(self, range_header: str, file_size: int) -> tuple[int, int] | None:
        value = range_header.strip()
        if not value.startswith("bytes="):
            return None

        spec = value[6:].strip()
        if "," in spec:
            return None

        if "-" not in spec:
            return None

        start_raw, end_raw = spec.split("-", 1)
        start_raw = start_raw.strip()
        end_raw = end_raw.strip()

        if not start_raw and not end_raw:
            return None

        try:
            if not start_raw:
                # Suffix range: "bytes=-N"
                suffix_len = int(end_raw, 10)
                if suffix_len <= 0:
                    return None
                start = max(0, file_size - suffix_len)
                end = file_size - 1
            else:
                start = int(start_raw, 10)
                if start < 0 or start >= file_size:
                    raise ValueError("unsatisfiable")
                if not end_raw:
                    end = file_size - 1
                else:
                    end = int(end_raw, 10)
                    if end < start:
                        return None
                    end = min(end, file_size - 1)
        except ValueError as exc:
            # Special-case unsatisfiable start offset (>= file_size).
            if str(exc) == "unsatisfiable":
                raise
            return None

        return start, end

    def _accepts_gzip(self) -> bool:
        encoding = self.headers.get("Accept-Encoding", "")
        return "gzip" in encoding.lower()

    def _should_compress(self, path: str, file_size: int) -> bool:
        if not self._accepts_gzip():
            return False
        if self.headers.get("Range"):
            # Keep range requests uncompressed for compatibility.
            return False
        if file_size < COMPRESS_MIN_BYTES:
            return False
        ext = os.path.splitext(path)[1].lower()
        return ext in COMPRESS_EXT

    def _send_gzip_file(self, path: str, send_body: bool) -> None:
        st = os.stat(path)
        ctype = self.guess_type(path)
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Encoding", "gzip")
        self.send_header("Vary", "Accept-Encoding")
        self.send_header("Last-Modified", self.date_time_string(st.st_mtime))
        self.send_header("Connection", "close")
        self.end_headers()

        if not send_body:
            self.close_connection = True
            return

        with open(path, "rb") as src:
            with gzip.GzipFile(
                fileobj=self.wfile,
                mode="wb",
                compresslevel=COMPRESS_LEVEL,
                mtime=0,
            ) as gz_out:
                shutil.copyfileobj(src, gz_out, length=64 * 1024)
        self.close_connection = True

    def _send_plain_file(self, path: str, send_body: bool) -> None:
        st = os.stat(path)
        file_size = st.st_size
        ctype = self.guess_type(path)
        range_header = self.headers.get("Range")

        if range_header:
            try:
                byte_range = self._parse_range(range_header, file_size)
            except ValueError:
                self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                self.send_header("Content-Range", f"bytes */{file_size}")
                self.send_header("Accept-Ranges", "bytes")
                self.end_headers()
                return
        else:
            byte_range = None

        if byte_range is not None:
            start, end = byte_range
            length = end - start + 1
            self.send_response(HTTPStatus.PARTIAL_CONTENT)
            self.send_header("Content-Type", ctype)
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
            self.send_header("Content-Length", str(length))
            self.send_header("Last-Modified", self.date_time_string(st.st_mtime))
            self.end_headers()

            if not send_body:
                return

            with open(path, "rb") as src:
                src.seek(start)
                remaining = length
                while remaining > 0:
                    chunk = src.read(min(64 * 1024, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
            return

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", ctype)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(file_size))
        self.send_header("Last-Modified", self.date_time_string(st.st_mtime))
        self.end_headers()

        if not send_body:
            return

        with open(path, "rb") as src:
            shutil.copyfileobj(src, self.wfile, length=64 * 1024)

    def _serve(self, send_body: bool) -> None:
        path = self.translate_path(self.path)

        # Delegate directory handling and 404 behavior to stdlib handler.
        if os.path.isdir(path) or not os.path.isfile(path):
            if send_body:
                super().do_GET()
            else:
                super().do_HEAD()
            return

        file_size = os.path.getsize(path)
        if self._should_compress(path, file_size):
            self._send_gzip_file(path, send_body=send_body)
            return

        self._send_plain_file(path, send_body=send_body)

    def do_GET(self) -> None:  # noqa: N802
        if self._request_path() == "/api/upload-disk":
            self._handle_get_disk(send_body=True)
            return
        if self._request_path() == "/api/upload-disk/files":
            self._handle_get_disk_files(send_body=True)
            return
        if self._request_path() == "/api/upload-disk/file":
            self._handle_download_disk_file(send_body=True)
            return
        self._serve(send_body=True)

    def do_HEAD(self) -> None:  # noqa: N802
        if self._request_path() == "/api/upload-disk":
            self._handle_get_disk(send_body=False)
            return
        if self._request_path() == "/api/upload-disk/files":
            self._handle_get_disk_files(send_body=False)
            return
        if self._request_path() == "/api/upload-disk/file":
            self._handle_download_disk_file(send_body=False)
            return
        self._serve(send_body=False)

    def do_POST(self) -> None:  # noqa: N802
        if self._request_path() == "/api/upload-disk":
            self._handle_post_disk()
            return
        if self._request_path() == "/api/upload-disk/import":
            self._handle_import_disk_file()
            return
        self.send_error(HTTPStatus.NOT_FOUND, "endpoint not found")

    def do_PUT(self) -> None:  # noqa: N802
        if self._request_path() == "/api/upload-disk/file":
            self._handle_put_disk_file()
            return
        self.send_error(HTTPStatus.NOT_FOUND, "endpoint not found")

    def do_DELETE(self) -> None:  # noqa: N802
        if self._request_path() == "/api/upload-disk":
            self._handle_delete_disk()
            return
        self.send_error(HTTPStatus.NOT_FOUND, "endpoint not found")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Serve static files with optional gzip content-encoding."
    )
    parser.add_argument("port", nargs="?", type=int, default=8080)
    parser.add_argument("directory", nargs="?", default="public")
    args = parser.parse_args()

    directory = os.path.abspath(args.directory)
    handler = partial(CompressedStaticHandler, directory=directory)
    with ThreadingHTTPServer(("0.0.0.0", args.port), handler) as httpd:
        print(f"Serving HTTP on 0.0.0.0:{args.port} (directory={directory})")
        print(
            "gzip config: "
            f"min_bytes={COMPRESS_MIN_BYTES} level={COMPRESS_LEVEL} "
            f"exts={','.join(sorted(COMPRESS_EXT))}"
        )
        httpd.serve_forever()


if __name__ == "__main__":
    main()
