#!/usr/bin/env python3
# web/server.py — my-agent 短视频生成 Web 面板（仅标准库，无第三方依赖）
#
# 用法:
#   python3 web/server.py            # 默认 0.0.0.0:8080
#   PORT=9000 python3 web/server.py  # 自定义端口
#
# 流程: 表单上传(视频素材 + 克隆音频 + 参考文案) -> 后台 clone 音色 -> 调
#       operator/tools/video_dub.sh 出片 -> 前端倒计时轮询 -> 下载成片。
import os, re, json, uuid, time, shutil, threading, subprocess, mimetypes
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(BASE)
TOOLS = os.path.join(ROOT, "operator", "tools")
VOICE = os.path.join(ROOT, "voice")
UPLOADS = os.path.join(BASE, "uploads")
OUTPUTS = os.path.join(BASE, "outputs")
os.makedirs(UPLOADS, exist_ok=True)
os.makedirs(OUTPUTS, exist_ok=True)

PORT = int(os.environ.get("PORT", "8080"))
HOST = os.environ.get("HOST", "0.0.0.0")
MAX_UPLOAD = int(os.environ.get("MAX_UPLOAD_MB", "500")) * 1024 * 1024

JOBS = {}
LOCK = threading.Lock()

# 用 opencode 免费模型把「参考文案/卖点」整理成口播稿（免 key）
OC_BIN = shutil.which("opencode") or "/usr/local/bin/opencode"
OC_MODEL = os.environ.get("OC_MODEL", "opencode/ling-3.1-flash-free")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
OC_LOCK = threading.Lock()   # 串行化 opencode 调用，避免并发抢同一个数据目录
N_VERSIONS = int(os.environ.get("N_VERSIONS", "3"))
ANGLES = [
    "信任背书：突出品牌/口碑/专业度或品质保证",
    "核心卖点：突出主要功能、参数、性能等硬实力",
    "使用场景：突出使用场景与解决的痛点、实际体验",
]


def _run(cmd, timeout=None):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def probe_duration(path):
    try:
        r = _run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                  "-of", "default=noprint_wrappers=1:nokey=1", path])
        return float(r.stdout.strip())
    except Exception:
        return 0.0


def make_script(reference, dur, feedback="", target_chars=None, angle=""):
    """用 opencode 免费模型，把「参考文案/卖点」整理成受时长约束的口播稿。失败返回空串。"""
    if target_chars is None:
        target_chars = max(50, int((dur - 5) * 3.2))   # 克隆语速约 3.2 字/秒(低估,宁短勿超)
    n_sent = max(4, round(target_chars / 20))
    prompt = (
        "你是短视频口播文案写手。把下面的『参考文案/素材』整理成一条用于配音+字幕的【口播稿】。\n"
        "要求：\n"
        f"1) 长度：约 {target_chars} 字（{int(target_chars*0.9)}~{int(target_chars*1.1)} 字），分成约 {n_sent} 句，每句 18~24 字，宁短勿超；\n"
        "2) 按语义断句，每句以换行分隔；\n"
        "3) 口语顺、连贯、有钩子，把信息融进话里，不要罗列参数；\n"
        "4) 忠于参考文案：只使用其中给出的信息与要求（如是否出现品牌名、结尾语、禁忌词等）；参考文案没写的，不要臆造；\n"
        "5) 只输出口播文案本身：不要解释、不要标题、不要序号、不要引号、不要空行。\n"
    )
    if angle:
        prompt += f"\n本条切入角度（要与其他版本明显不同）：{angle}\n"
    if feedback:
        prompt += f"\n【上一版问题，务必修正】{feedback}\n"
    prompt += "\n参考文案：\n" + reference
    env = dict(os.environ)
    env["PATH"] = "/usr/local/bin:" + env.get("PATH", "")
    try:
        with OC_LOCK:
            r = subprocess.run([OC_BIN, "run", "--model", OC_MODEL, prompt],
                               cwd=ROOT, capture_output=True, text=True, timeout=180, env=env)
        out = ANSI.sub("", r.stdout or "")
        lines = []
        for ln in out.splitlines():
            s = ln.strip()
            if not s or s.startswith(">") or s.startswith("#"):
                continue
            lines.append(s)
        return "\n".join(lines).strip()
    except Exception:
        return ""


def probe_narration(video, script_segments, voice):
    """用 video_dub --probe 实测配音时长（秒）。失败返回 None。"""
    try:
        r = _run([os.path.join(TOOLS, "video_dub.sh"), video, script_segments,
                  "--voice", voice, "--probe", "--fg"], timeout=300)
        m = re.search(r"配音\s*([\d.]+)s", (r.stdout or "") + (r.stderr or ""))
        return float(m.group(1)) if m else None
    except Exception:
        return None


def to_segments(text):
    """口播稿 -> video_dub 的分段（换行视为段分隔）"""
    return re.sub(r"[ \t]*\r?\n+[ \t]*", "|", text.strip())


def worker(job_id, video, audio, text, dur):
    job = JOBS[job_id]
    tmp_voice = "vjob_" + job_id
    try:
        # 音频统一转 16k 单声道 wav，便于克隆
        wav = os.path.join(UPLOADS, job_id + "_ref.wav")
        _run(["ffmpeg", "-y", "-i", audio, "-ar", "16000", "-ac", "1",
              "-c:a", "pcm_s16le", wav])
        job["status"] = "cloning"
        r = _run([os.path.join(VOICE, "cosyvoice.sh"), "add", tmp_voice, wav])
        if r.returncode != 0:
            job["status"] = "error"
            job["error"] = "音色克隆失败：" + (r.stderr or r.stdout)[-400:]
            return
        # 一次生成 N 条（不同角度）：模型整理文案 + probe 实测语速迭代适配时长，再分别合成
        outs = []
        job["outputs"] = outs
        last_err = ""
        for i in range(N_VERSIONS):
            angle = ANGLES[i % len(ANGLES)]
            job["status"] = "writing"; job["progress"] = f"文案 {i+1}/{N_VERSIONS}"
            script = make_script(text, dur, angle=angle) or text
            seg = to_segments(script)
            for _ in range(3):
                narr = probe_narration(video, seg, tmp_voice)
                job["narration"] = round(narr, 1) if narr else None
                if not narr or (0.80 * dur <= narr <= dur + 0.5):
                    break
                chars = len(seg.replace("|", ""))
                want = max(40, int(chars * dur / narr * 0.97))
                if narr < 0.80 * dur:
                    fb = f"上一版配音只有 {narr:.0f}s，视频 {dur:.0f}s，太短，请加长到约 {want} 字，务必写满。"
                else:
                    fb = f"上一版配音 {narr:.0f}s 超过视频 {dur:.0f}s，请精简到约 {want} 字（在句中完整断句，别砍词）。"
                ns = make_script(text, dur, feedback=fb, angle=angle)
                if not ns:
                    break
                script = ns; seg = to_segments(script)
            if not seg:
                last_err = "参考文案为空"; continue
            job["status"] = "generating"; job["progress"] = f"合成 {i+1}/{N_VERSIONS}"
            out = os.path.join(OUTPUTS, f"{job_id}_{i+1}.mp4")
            r = _run([os.path.join(TOOLS, "video_dub.sh"), video, seg,
                      "--voice", tmp_voice, "--fg", "--no-send", "--out", out])   # 不用 --fit，避免砍词
            if r.returncode == 0 and os.path.exists(out) and os.path.getsize(out) > 0:
                outs.append({"n": i + 1, "url": f"/download/{job_id}/{i+1}",
                             "script": script, "angle": angle, "size": os.path.getsize(out)})
                job["script"] = script
            else:
                last_err = (r.stderr or r.stdout)[-400:]
        if outs:
            job["status"] = "done"; job["out"] = outs[0]; job["size"] = outs[0]["size"]
        else:
            job["status"] = "error"; job["error"] = "生成失败：" + last_err
    except Exception as e:  # noqa
        job["status"] = "error"; job["error"] = repr(e)
    finally:
        _run([os.path.join(VOICE, "cosyvoice.sh"), "del", tmp_voice])
        try: os.remove(os.path.join(UPLOADS, job_id + "_ref.wav"))
        except OSError: pass


def parse_multipart(body, boundary):
    fields, files = {}, {}
    delim = b"--" + boundary
    for part in body.split(delim):
        if not part or part in (b"--\r\n", b"--", b"\r\n"):
            continue
        if part.startswith(b"\r\n"):
            part = part[2:]
        if part.endswith(b"\r\n"):
            part = part[:-2]
        if part.endswith(b"--"):
            part = part[:-2]
        if b"\r\n\r\n" not in part:
            continue
        head, data = part.split(b"\r\n\r\n", 1)
        if data.endswith(b"\r\n"):
            data = data[:-2]
        name = filename = None
        for line in head.decode("utf-8", "replace").split("\r\n"):
            if line.lower().startswith("content-disposition"):
                for kv in line.split(";"):
                    kv = kv.strip()
                    if kv.startswith("name="):
                        name = kv[5:].strip().strip('"')
                    elif kv.startswith("filename="):
                        filename = kv[9:].strip().strip('"')
        if name is None:
            continue
        if filename:
            files[name] = (filename, data)
        else:
            fields[name] = data.decode("utf-8", "replace")
    return fields, files


class Handler(BaseHTTPRequestHandler):
    server_version = "myagent-web/1.0"

    def log_message(self, fmt, *args):
        pass

    def _json(self, obj, code=200):
        data = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            return self._serve_file(os.path.join(BASE, "index.html"))
        if self.path == "/api/health":
            return self._json({"ok": True})
        m = re.match(r"^/api/status/([0-9a-zA-Z_-]+)$", self.path)
        if m:
            with LOCK:
                job = JOBS.get(m.group(1))
                if not job:
                    return self._json({"error": "not found"}, 404)
                return self._json({
                    "status": job["status"], "error": job.get("error"),
                    "elapsed": round(time.time() - job["t0"], 1),
                    "size": job.get("size"), "script": job.get("script"),
                    "narration": job.get("narration"),
                    "progress": job.get("progress"),
                    "outputs": job.get("outputs") or [],
                })
        m = re.match(r"^/download/([0-9a-zA-Z_-]+)(?:/(\d+))?$", self.path)
        if m:
            jid, n = m.group(1), m.group(2)
            out = os.path.join(OUTPUTS, f"{jid}_{n}.mp4" if n else jid + ".mp4")
            if not os.path.exists(out):
                return self._json({"error": "not found"}, 404)
            return self._serve_file(out, download=True)
        return self._json({"error": "not found"}, 404)

    def do_POST(self):
        if self.path != "/api/generate":
            return self._json({"error": "not found"}, 404)
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_UPLOAD:
                return self._json({"error": f"上传为空或超过 {MAX_UPLOAD // 1048576}MB"}, 413)
            ctype = self.headers.get("Content-Type", "")
            bm = re.search(r"boundary=([^;]+)", ctype)
            if not bm:
                return self._json({"error": "缺少 multipart boundary"}, 400)
            body = self.rfile.read(length)
            fields, files = parse_multipart(body, bm.group(1).strip().strip('"').encode())
            if "video" not in files:
                return self._json({"error": "缺少视频素材"}, 400)
            if "audio" not in files:
                return self._json({"error": "缺少克隆音频素材"}, 400)
            text = fields.get("text", "").strip()
            if not text:
                return self._json({"error": "缺少参考文案"}, 400)

            job_id = uuid.uuid4().hex[:12]
            vname = files["video"][0] or "video.mp4"
            vext = os.path.splitext(vname)[1] or ".mp4"
            aname = files["audio"][0] or "audio.wav"
            aext = os.path.splitext(aname)[1] or ".wav"
            vpath = os.path.join(UPLOADS, job_id + "_video" + vext)
            apath = os.path.join(UPLOADS, job_id + "_audio" + aext)
            with open(vpath, "wb") as f:
                f.write(files["video"][1])
            with open(apath, "wb") as f:
                f.write(files["audio"][1])

            dur = probe_duration(vpath)
            estimate = max(30, int(dur * 0.6) + 25)
            with LOCK:
                JOBS[job_id] = {"status": "queued", "t0": time.time(), "estimate": estimate}
            threading.Thread(target=worker, args=(job_id, vpath, apath, text, dur), daemon=True).start()
            return self._json({"id": job_id, "estimate": estimate})
        except Exception as e:  # noqa
            return self._json({"error": repr(e)}, 500)

    def _serve_file(self, path, download=False):
        if not os.path.exists(path):
            self.send_error(404); return
        ctype = mimetypes.guess_type(path)[0] or "application/octet-stream"
        size = os.path.getsize(path)
        rng = self.headers.get("Range")
        start, end = 0, size - 1
        if rng:
            mm = re.match(r"bytes=(\d*)-(\d*)", rng)
            if mm:
                if mm.group(1):
                    start = int(mm.group(1))
                if mm.group(2):
                    end = int(mm.group(2))
                end = min(end, size - 1)
        length = end - start + 1
        self.send_response(206 if rng else 200)
        self.send_header("Content-Type", ctype)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if rng:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        if download:
            self.send_header("Content-Disposition", f'attachment; filename="{os.path.basename(path)}"')
        self.end_headers()
        with open(path, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk = f.read(min(65536, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)


if __name__ == "__main__":
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"my-agent 短视频面板: http://{HOST}:{PORT}  (repo={ROOT})")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
