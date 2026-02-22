#!/usr/bin/env python3
"""Static server with optional forced gzip content-encoding for selected extensions."""

from __future__ import annotations

import argparse
import gzip
import os
import shutil
from functools import partial
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

        if send_body:
            super().do_GET()
        else:
            super().do_HEAD()

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

