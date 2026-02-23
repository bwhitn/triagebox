#!/usr/bin/env python3
"""Static server with optional forced gzip content-encoding for selected extensions."""

from __future__ import annotations

import argparse
import gzip
import os
import shutil
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


class CompressedStaticHandler(SimpleHTTPRequestHandler):
    server_version = "CompressedHTTP/1.0"

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
        self._serve(send_body=True)

    def do_HEAD(self) -> None:  # noqa: N802
        self._serve(send_body=False)


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
