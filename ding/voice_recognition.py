#!/usr/bin/env python3
"""
本地语音识别模块 - 基于 SenseVoice.cpp 共享库
功能：将音频文件（支持 amr/wav/mp3 等）转为文本
性能优化：模型常驻内存，避免每次识别重新加载（节省 ~0.8s/次）
"""
import ctypes
import os
import re
import subprocess
import sys
import tempfile

from logger import app_logger as logger

# 动态获取项目目录
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)

# SenseVoice 路径配置
SENSEVOICE_DIR = "/home/dministrator/SenseVoice.cpp"
SENSEVOICE_SO = os.path.join(PROJECT_DIR, "libs", "libsensevoice.so")
SENSEVOICE_MODEL = os.path.join(SENSEVOICE_DIR, "models", "sense-voice-small-q6_k.gguf")

# ctypes 接口
_lib = None
_ctx = None


def _load_library() -> ctypes.CDLL:
    """加载 SenseVoice 共享库"""
    global _lib
    if _lib is not None:
        return _lib

    if not os.path.exists(SENSEVOICE_SO):
        raise FileNotFoundError(f"共享库不存在: {SENSEVOICE_SO}")

    # 设置库搜索路径
    os.environ.setdefault("LD_LIBRARY_PATH", "")
    ggml_path = os.path.join(SENSEVOICE_DIR, "build", "lib")
    if ggml_path not in os.environ["LD_LIBRARY_PATH"]:
        os.environ["LD_LIBRARY_PATH"] = f"{ggml_path}:{os.environ['LD_LIBRARY_PATH']}".rstrip(":")

    _lib = ctypes.CDLL(SENSEVOICE_SO)

    # 定义函数签名
    _lib.sensevoice_load_model.argtypes = [ctypes.c_char_p, ctypes.c_int]
    _lib.sensevoice_load_model.restype = ctypes.c_void_p

    _lib.sensevoice_recognize.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    _lib.sensevoice_recognize.restype = ctypes.c_char_p

    _lib.sensevoice_free_text.argtypes = [ctypes.c_char_p]
    _lib.sensevoice_free_text.restype = None

    _lib.sensevoice_free_model.argtypes = [ctypes.c_void_p]
    _lib.sensevoice_free_model.restype = None

    return _lib


def _load_model() -> ctypes.c_void_p:
    """加载模型（常驻内存）"""
    global _ctx
    if _ctx is not None:
        return _ctx

    if not os.path.exists(SENSEVOICE_MODEL):
        raise FileNotFoundError(f"模型文件不存在: {SENSEVOICE_MODEL}")

    lib = _load_library()
    logger.info(f"[SenseVoice] 正在加载模型: {SENSEVOICE_MODEL}")
    _ctx = lib.sensevoice_load_model(SENSEVOICE_MODEL.encode("utf-8"), 4)
    if not _ctx:
        raise RuntimeError("模型加载失败")
    logger.info("[SenseVoice] 模型加载成功")
    return _ctx


def _convert_to_wav(input_path: str, output_path: str) -> bool:
    """将音频文件转换为 16kHz 单声道 WAV 格式"""
    try:
        cmd = [
            "ffmpeg", "-y", "-i", input_path,
            "-ar", "16000", "-ac", "1",
            "-c:a", "pcm_s16le",
            output_path
        ]
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            logger.error(f"ffmpeg 转换失败: {result.stderr[:500]}")
            return False
        return True
    except subprocess.TimeoutExpired:
        logger.error("ffmpeg 转换超时")
        return False
    except Exception as e:
        logger.error(f"ffmpeg 转换异常: {e}")
        return False


def _parse_output(output: str) -> str:
    """解析 SenseVoice 输出，移除标签，提取纯文本"""
    # 移除所有 <|xxx|> 标签
    text = re.sub(r"<\|[a-z_]+\|>", "", output)
    return text.strip()


def recognize_audio(audio_path: str) -> str:
    """
    识别音频文件，返回文本

    Args:
        audio_path: 音频文件路径（支持 amr/wav/mp3 等）

    Returns:
        识别出的文本，失败返回空字符串
    """
    if not os.path.exists(audio_path):
        logger.error(f"音频文件不存在: {audio_path}")
        return ""

    # 检查是否已经是 16kHz WAV
    is_wav = audio_path.lower().endswith(".wav")
    wav_path = audio_path
    temp_wav = None

    if not is_wav:
        temp_wav = tempfile.mktemp(suffix=".wav")
        logger.info(f"转换音频格式: {audio_path} -> {temp_wav}")
        if not _convert_to_wav(audio_path, temp_wav):
            return ""
        wav_path = temp_wav

    try:
        ctx = _load_model()
        lib = _load_library()

        logger.info(f"开始语音识别: {wav_path}")
        text_ptr = lib.sensevoice_recognize(ctx, wav_path.encode("utf-8"), 4)

        if not text_ptr:
            logger.error("SenseVoice 识别返回空结果")
            return ""

        text = ctypes.string_at(text_ptr).decode("utf-8", errors="ignore")
        lib.sensevoice_free_text(text_ptr)

        text = _parse_output(text)
        logger.info(f"语音识别结果: {text[:100]}...")
        return text

    except Exception as e:
        logger.error(f"语音识别异常: {e}")
        return ""
    finally:
        if temp_wav and os.path.exists(temp_wav):
            try:
                os.unlink(temp_wav)
            except Exception:
                pass


def recognize_audio_from_url(download_url: str, temp_dir: str = "/tmp/autobot_voice") -> str:
    """
    从 URL 下载音频并识别

    Args:
        download_url: 音频下载地址
        temp_dir: 临时文件存放目录

    Returns:
        识别出的文本
    """
    import requests

    os.makedirs(temp_dir, exist_ok=True)

    try:
        resp = requests.get(download_url, timeout=60)
        if resp.status_code != 200:
            logger.error(f"下载音频失败: HTTP {resp.status_code}")
            return ""

        temp_path = os.path.join(temp_dir, f"voice_{os.getpid()}_{int(__import__('time').time())}.amr")
        with open(temp_path, "wb") as f:
            f.write(resp.content)

        logger.info(f"语音文件已下载: {temp_path}, 大小: {len(resp.content)} bytes")

        text = recognize_audio(temp_path)

        try:
            os.unlink(temp_path)
        except Exception:
            pass

        return text

    except Exception as e:
        logger.error(f"下载音频异常: {e}")
        return ""


def cleanup():
    """释放模型资源（进程退出时调用）"""
    global _ctx
    if _ctx is not None and _lib is not None:
        logger.info("[SenseVoice] 释放模型资源")
        _lib.sensevoice_free_model(_ctx)
        _ctx = None


if __name__ == "__main__":
    import time

    print("=== SenseVoice 语音识别测试 ===")

    test_wav = "/tmp/test_zh.wav"
    if os.path.exists(test_wav):
        t0 = time.time()
        text = recognize_audio(test_wav)
        print(f"识别结果: {text}")
        print(f"耗时: {time.time() - t0:.2f}s")
    else:
        print(f"测试文件不存在: {test_wav}")

    cleanup()
