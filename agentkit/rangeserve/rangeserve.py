#!/usr/bin/env python3
import os, re, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.environ.get("ROOT", "/tmp/zfsv3/sata11/18072858035/data")
PORT = int(os.environ.get("PORT", "8099"))

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def do_GET(self):
        path = os.path.abspath(os.path.join(ROOT, urllib.parse.unquote(self.path).lstrip("/")))
        if not path.startswith(ROOT) or not os.path.isfile(path):
            self.send_error(404); return
        size = os.path.getsize(path)
        rng = self.headers.get("Range")
        start, end = 0, size - 1
        if rng:
            m = re.match(r"bytes=(\d*)-(\d*)", rng)
            if m:
                if m.group(1): start = int(m.group(1))
                if m.group(2): end = int(m.group(2))
        self.send_response(206 if rng else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if rng: self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        with open(path, "rb") as f:
            f.seek(start)
            left = end - start + 1
            while left > 0:
                b = f.read(min(262144, left))
                if not b: break
                try: self.wfile.write(b)
                except OSError: break
                left -= len(b)

ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
