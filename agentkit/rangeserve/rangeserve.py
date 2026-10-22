#!/usr/bin/env python3
import os, re, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.realpath(os.environ.get("ROOT", "/tmp/zfsv3/sata11/18072858035/data"))
PORT = int(os.environ.get("PORT", "8099"))

CHUNK = 1024 * 1024


def parse_range(rng, size):
    """Return (start, end) or None for invalid/unsatisfiable."""
    m = re.fullmatch(r"bytes=(\d*)-(\d*)", (rng or "").strip())
    if not m:
        return None
    a, b = m.group(1), m.group(2)
    if not a and not b:
        return None
    if not a:                      # suffix: bytes=-N  (last N bytes)
        n = int(b)
        if n <= 0:
            return None
        return max(0, size - n), size - 1
    start = int(a)
    end = size - 1 if not b else min(int(b), size - 1)
    if start >= size or start > end:
        return None
    return start, end


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _serve(self, head_only):
        req_path = urllib.parse.urlparse(self.path).path
        path = os.path.realpath(os.path.join(
            ROOT, urllib.parse.unquote(req_path).lstrip("/")))
        if os.path.commonpath([ROOT, path]) != ROOT or not os.path.isfile(path):
            self.send_error(404)
            return
        size = os.path.getsize(path)
        rng = self.headers.get("Range")
        if rng:
            span = parse_range(rng, size)
            if span is None:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            start, end = span
        else:
            start, end = 0, size - 1
        self.send_response(206 if rng else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if rng:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if head_only:
            return
        with open(path, "rb") as f:
            f.seek(start)
            left = end - start + 1
            while left > 0:
                b = f.read(min(CHUNK, left))
                if not b:
                    break
                try:
                    self.wfile.write(b)
                except (BrokenPipeError, ConnectionResetError):
                    break
                left -= len(b)

    def do_GET(self):
        self._serve(False)

    def do_HEAD(self):
        self._serve(True)


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


Server(("0.0.0.0", PORT), H).serve_forever()
