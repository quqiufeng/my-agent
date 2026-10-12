#!/usr/bin/env python3
# wechat-ocr/ocr_rapidd.py — 常驻 RapidOCR 服务（PP-OCRv4/v5，onnxruntime）
# 监听 127.0.0.1:8799，POST 图片二进制 → {"boxes":[{x,y,w,h,text}...]}
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from rapidocr_onnxruntime import RapidOCR

ENG = RapidOCR()
PORT = 8799


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        data = self.rfile.read(n)
        path = "/tmp/myagent_rapid.png"
        with open(path, "wb") as f:
            f.write(data)
        try:
            res, _ = ENG(path)
        except Exception as e:
            res = []
        boxes = []
        for item in (res or []):
            box, text = item[0], item[1]
            xs = [p[0] for p in box]
            ys = [p[1] for p in box]
            boxes.append({
                "x": int(min(xs)), "y": int(min(ys)),
                "w": int(max(xs) - min(xs)), "h": int(max(ys) - min(ys)),
                "text": text,
            })
        out = json.dumps({"boxes": boxes}, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), H).serve_forever()
