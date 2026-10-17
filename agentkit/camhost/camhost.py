#!/usr/bin/env python3
"""camhost.py — 把本机 USB 摄像头 / 麦克风暴露成局域网 HTTP 流。

只用标准库 + ffmpeg/arecord，不需要 pip 依赖。

接口：
  GET /            说明页
  GET /info        JSON：设备、分辨率、麦克风、客户端数
  GET /video       MJPEG 流（multipart/x-mixed-replace）
  GET /audio       WAV 流（16k/单声道/16bit PCM，持续）
  GET /snap        当前一帧 JPEG（可直接 <img> 或抓图）

环境变量：
  CAM_DEV=/dev/video0   CAM_SIZE=1280x720   CAM_FPS=15   CAM_QUALITY=5
  MIC_DEV=plughw:2,0    MIC_RATE=16000      PORT=8080
  IDLE_STOP=10          最后一个客户端断开后停采集的秒数（0=不主动停）

启动时会按需拉起 ffmpeg/arecord，客户端全部断开 IDLE_STOP 秒后停止，省 CPU。
"""
import json
import os
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CFG = {
    "cam": os.environ.get("CAM_DEV", "/dev/video0"),
    "size": os.environ.get("CAM_SIZE", "1280x720"),
    "fps": os.environ.get("CAM_FPS", "15"),
    "quality": os.environ.get("CAM_QUALITY", "5"),
    "mic": os.environ.get("MIC_DEV", "plughw:2,0"),
    "rate": int(os.environ.get("MIC_RATE", "16000")),
    "port": int(os.environ.get("PORT", "8080")),
    "idle_stop": float(os.environ.get("IDLE_STOP", "10")),
}

START = time.time()

lock = threading.Lock()
video_clients = set()
audio_clients = set()
latest_jpeg = [None]
video_proc = [None]
audio_proc = [None]
video_starting = [False]
audio_starting = [False]
idle_since = [time.time()]
fps_counter = [0, 0.0]  # 帧数, 最近一次统计时间


# ---------------- 客户端管理 ----------------

def add_client(kind, sock):
    with lock:
        (video_clients if kind == "video" else audio_clients).add(sock)
        idle_since[0] = None
    ensure_started()


def drop_client(kind, sock):
    with lock:
        (video_clients if kind == "video" else audio_clients).discard(sock)
        if not video_clients and not audio_clients:
            idle_since[0] = time.time()
    try:
        sock.close()
    except OSError:
        pass


def broadcast(kind, data):
    with lock:
        clients = list(video_clients if kind == "video" else audio_clients)
    dead = []
    for s in clients:
        try:
            s.sendall(data)
        except (OSError, socket.timeout):
            dead.append(s)
    for s in dead:
        drop_client(kind, s)


# ---------------- 采集 ----------------

def ensure_video():
    """确保摄像头采集在跑（/snap 不需要注册客户端）。"""
    with lock:
        if video_proc[0] is not None or video_starting[0]:
            return
        video_starting[0] = True
        idle_since[0] = time.time()
    threading.Thread(target=video_loop, daemon=True).start()


def video_loop():
    cmd = [
        "ffmpeg", "-loglevel", "error", "-nostdin",
        "-f", "v4l2", "-video_size", CFG["size"], "-framerate", CFG["fps"],
        "-i", CFG["cam"],
        "-f", "mjpeg", "-q:v", CFG["quality"], "-",
    ]
    while True:
        try:
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, bufsize=0)
            video_proc[0] = p
            parse_jpeg_stream(p.stdout)
        except Exception as e:  # noqa: BLE001
            print(f"[camhost] video: {e}", file=sys.stderr)
        finally:
            if video_proc[0]:
                try:
                    video_proc[0].kill()
                except OSError:
                    pass
                video_proc[0] = None
            video_starting[0] = False
        time.sleep(1)
        if not video_clients:
            return


def parse_jpeg_stream(stream):
    buf = bytearray()
    while True:
        chunk = stream.read(65536)
        if not chunk:
            return
        buf += chunk
        while True:
            start = buf.find(b"\xff\xd8")
            if start < 0:
                buf.clear()
                break
            end = buf.find(b"\xff\xd9", start + 2)
            if end < 0:
                if start:
                    del buf[:start]
                break
            frame = bytes(buf[start:end + 2])
            del buf[:end + 2]
            latest_jpeg[0] = frame
            fps_counter[0] += 1
            broadcast("video",
                      b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: "
                      + str(len(frame)).encode() + b"\r\n\r\n" + frame + b"\r\n")


def audio_loop():
    cmd = ["arecord", "-D", CFG["mic"], "-f", "S16_LE", "-r", str(CFG["rate"]),
           "-c", "1", "-q", "-t", "raw", "-"]
    while True:
        try:
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, bufsize=0)
            audio_proc[0] = p
            while True:
                chunk = p.stdout.read(4096)
                if not chunk:
                    break
                broadcast("audio", chunk)
        except Exception as e:  # noqa: BLE001
            print(f"[camhost] audio: {e}", file=sys.stderr)
        finally:
            if audio_proc[0]:
                try:
                    audio_proc[0].kill()
                except OSError:
                    pass
                audio_proc[0] = None
        time.sleep(1)
        if not audio_clients:
            return


def ensure_started():
    with lock:
        need_v = bool(video_clients) and video_proc[0] is None
        need_a = bool(audio_clients) and audio_proc[0] is None
        if not need_v and not need_a:
            return
    if need_v:
        ensure_video()
    if need_a:
        threading.Thread(target=audio_loop, daemon=True).start()


def idle_watchdog():
    while True:
        time.sleep(1)
        since = idle_since[0]
        if since is None or not CFG["idle_stop"]:
            continue
        if time.time() - since < CFG["idle_stop"]:
            continue
        with lock:
            if video_clients or audio_clients:
                continue
            for tag, holder in (("video", video_proc), ("audio", audio_proc)):
                p = holder[0]
                if p:
                    try:
                        p.kill()
                    except OSError:
                        pass
                    holder[0] = None


# ---------------- HTTP ----------------

def wav_header(rate, seconds=3600):
    data = rate * 2 * seconds
    return (b"RIFF" + (36 + data).to_bytes(4, "little") + b"WAVEfmt "
            + (16).to_bytes(4, "little") + (1).to_bytes(2, "little")
            + (1).to_bytes(2, "little") + rate.to_bytes(4, "little")
            + (rate * 2).to_bytes(4, "little") + (2).to_bytes(2, "little")
            + (16).to_bytes(2, "little") + b"data"
            + data.to_bytes(4, "little"))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # 少打日志
        pass

    def do_GET(self):  # noqa: N802
        path = self.path.split("?")[0]
        if path == "/info":
            self.send_json()
        elif path == "/video":
            self.stream_video()
        elif path == "/audio":
            self.stream_audio()
        elif path == "/snap":
            self.snapshot()
        elif path == "/":
            self.index()
        else:
            self.send_error(404)

    def send_json(self):
        with lock:
            nv, na = len(video_clients), len(audio_clients)
        body = json.dumps({
            "video": {"device": CFG["cam"], "size": CFG["size"], "fps": CFG["fps"],
                      "clients": nv},
            "audio": {"device": CFG["mic"], "rate": CFG["rate"],
                      "channels": 1, "clients": na},
            "uptime": round(time.time() - START, 1),
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def index(self):
        body = ("<h2>camhost</h2><p><img src='/snap'></p>"
                "<p><a href='/video'>/video</a> MJPEG | "
                "<a href='/audio'>/audio</a> WAV | "
                "<a href='/info'>/info</a></p>").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def snapshot(self):
        ensure_video()
        deadline = time.time() + 10
        while latest_jpeg[0] is None and time.time() < deadline:
            time.sleep(0.2)
        frame = latest_jpeg[0]
        if not frame:
            self.send_error(503, "camera not ready")
            return
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(frame)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(frame)

    def stream_video(self):
        self.send_response(200)
        self.send_header("Content-Type",
                         "multipart/x-mixed-replace; boundary=frame")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        sock = self.connection
        sock.settimeout(5)
        add_client("video", sock)
        try:
            while True:
                time.sleep(1)
                if self.wfile.closed:
                    break
        except (OSError, ValueError):
            pass
        finally:
            drop_client("video", sock)

    def stream_audio(self):
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        sock = self.connection
        sock.settimeout(5)
        try:
            sock.sendall(wav_header(CFG["rate"]))
        except OSError:
            self.close_connection = True
            return
        add_client("audio", sock)
        try:
            while True:
                time.sleep(1)
                if self.wfile.closed:
                    break
        except (OSError, ValueError):
            pass
        finally:
            drop_client("audio", sock)


def main():
    threading.Thread(target=idle_watchdog, daemon=True).start()
    srv = ThreadingHTTPServer(("0.0.0.0", CFG["port"]), Handler)
    srv.daemon_threads = True
    print(f"[camhost] http://0.0.0.0:{CFG['port']}  cam={CFG['cam']} "
          f"{CFG['size']}@{CFG['fps']}  mic={CFG['mic']}@{CFG['rate']}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
