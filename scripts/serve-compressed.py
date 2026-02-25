#!/usr/bin/env python3
"""Static server with optional forced gzip content-encoding for selected extensions."""

from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import shutil
import tempfile
from urllib.parse import urlsplit
from functools import partial
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from typing import Iterable, Set


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


class CompressedStaticHandler(SimpleHTTPRequestHandler):
    server_version = "CompressedHTTP/1.0"

    def _request_path(self) -> str:
        return urlsplit(self.path).path

    def _uploads_dir(self) -> str:
        return os.path.join(self.directory, DISK_UPLOAD_SUBDIR)

    def _uploaded_disk_path(self) -> str:
        return os.path.join(self._uploads_dir(), DISK_UPLOAD_FILENAME)

    def _sanitize_filename(self, value: str) -> str:
        if not value:
            return "uploaded.img"
        base = os.path.basename(value.strip())
        cleaned = re.sub(r"[^A-Za-z0-9._-]+", "_", base).strip("._")
        return cleaned or "uploaded.img"

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
        content_length_raw = self.headers.get("Content-Length", "").strip()
        if not content_length_raw:
            self._send_json(HTTPStatus.LENGTH_REQUIRED, {"error": "Content-Length header is required"})
            return
        try:
            content_length = int(content_length_raw, 10)
        except ValueError:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid Content-Length header"})
            return
        if content_length <= 0:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "request body must be non-empty"})
            return
        if content_length > DISK_UPLOAD_MAX_BYTES:
            self._send_json(
                HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                {"error": f"disk upload exceeds max size ({DISK_UPLOAD_MAX_BYTES} bytes)"},
            )
            return

        uploads_dir = self._uploads_dir()
        os.makedirs(uploads_dir, exist_ok=True)

        target_path = self._uploaded_disk_path()
        fd, tmp_path = tempfile.mkstemp(prefix=".disk-upload-", suffix=".tmp", dir=uploads_dir)
        try:
            with os.fdopen(fd, "wb") as tmp_out:
                remaining = content_length
                while remaining > 0:
                    chunk = self.rfile.read(min(1024 * 1024, remaining))
                    if not chunk:
                        raise OSError("request body ended unexpectedly")
                    tmp_out.write(chunk)
                    remaining -= len(chunk)
            os.replace(tmp_path, target_path)
        except OSError as exc:
            try:
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)
            except OSError:
                pass
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": f"failed to store uploaded disk: {exc}"})
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
        self._serve(send_body=True)

    def do_HEAD(self) -> None:  # noqa: N802
        if self._request_path() == "/api/upload-disk":
            self._handle_get_disk(send_body=False)
            return
        self._serve(send_body=False)

    def do_POST(self) -> None:  # noqa: N802
        if self._request_path() == "/api/upload-disk":
            self._handle_post_disk()
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
