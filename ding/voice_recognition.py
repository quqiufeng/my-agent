#!/usr/bin/env python3
"""
本地语音识别模块 - 基于 SenseVoice.cpp
功能：将音频文件（支持 amr/wav/mp3 等）转为文本
"""
import os
import re
import subprocess
import tempfile
import shutil

from logger import app_logger as logger


# SenseVoice.cpp 路径配置
SENSEVOICE_DIR = "/home/dministrator/SenseVoice.cpp"
SENSEVOICE_BIN = os.path.join(SENSEVOICE_DIR, "bin", "sense-voice-main")
SENSEVOICE_MODEL = os.path.join(SENSEVOICE_DIR, "models", "sense-voice-small-q6_k.gguf")


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


def _run_sensevoice(wav_path: str) -> str:
    """调用 SenseVoice.cpp 识别音频"""
    if not os.path.exists(SENSEVOICE_BIN):
        raise FileNotFoundError(f"SenseVoice 可执行文件不存在: {SENSEVOICE_BIN}")
    if not os.path.exists(SENSEVOICE_MODEL):
        raise FileNotFoundError(f"SenseVoice 模型不存在: {SENSEVOICE_MODEL}")

    cmd = [
        SENSEVOICE_BIN,
        "-m", SENSEVOICE_MODEL,
        wav_path,
        "-t", "4",           # 4 线程
        "-l", "auto",        # 自动检测语言
        "-itn",              # 使用逆文本正则化（包含标点）
        "-ng",               # 不使用 GPU（CPU 已很快，且避免 CUDA 初始化开销）
    ]

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=60, cwd=SENSEVOICE_DIR
        )

        if result.returncode != 0:
            logger.error(f"SenseVoice 识别失败: {result.stderr[:500]}")
            return ""

        return result.stdout

    except subprocess.TimeoutExpired:
        logger.error("SenseVoice 识别超时")
        return ""
    except Exception as e:
        logger.error(f"SenseVoice 识别异常: {e}")
        return ""


def _parse_sensevoice_output(output: str) -> str:
    """解析 SenseVoice 输出，提取纯文本"""
    lines = output.strip().split("\n")
    texts = []

    for line in lines:
        # 匹配格式: [start-end] <|zh|><|NEUTRAL|><|Speech|><|withitn|>文本内容
        # 或: [start-end] 文本内容
        match = re.search(r"\[\d+\.\d+-\d+\.\d+\]\s*(.*)", line)
        if match:
            text = match.group(1)
            # 移除 SenseVoice 的标签（如 <|zh|>, <|NEUTRAL|> 等）
            text = re.sub(r"<\|[a-z_]+\|>", "", text)
            text = text.strip()
            if text:
                texts.append(text)

    return " ".join(texts)


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
        # 需要转换格式
        temp_wav = tempfile.mktemp(suffix=".wav")
        logger.info(f"转换音频格式: {audio_path} -> {temp_wav}")
        if not _convert_to_wav(audio_path, temp_wav):
            return ""
        wav_path = temp_wav

    try:
        logger.info(f"开始语音识别: {wav_path}")
        output = _run_sensevoice(wav_path)
        text = _parse_sensevoice_output(output)
        logger.info(f"语音识别结果: {text[:100]}...")
        return text
    finally:
        # 清理临时文件
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

    # 下载音频文件
    try:
        resp = requests.get(download_url, timeout=60)
        if resp.status_code != 200:
            logger.error(f"下载音频失败: HTTP {resp.status_code}")
            return ""

        # 保存临时文件
        temp_path = os.path.join(temp_dir, f"voice_{os.getpid()}_{int(time.time())}.amr")
        with open(temp_path, "wb") as f:
            f.write(resp.content)

        logger.info(f"语音文件已下载: {temp_path}, 大小: {len(resp.content)} bytes")

        # 识别
        text = recognize_audio(temp_path)

        # 清理下载的文件
        try:
            os.unlink(temp_path)
        except Exception:
            pass

        return text

    except Exception as e:
        logger.error(f"下载音频异常: {e}")
        return ""


if __name__ == "__main__":
    # 测试
    import time

    print("=== SenseVoice 语音识别测试 ===")

    # 测试已有的 wav 文件
    test_wav = "/tmp/test_zh.wav"
    if os.path.exists(test_wav):
        text = recognize_audio(test_wav)
        print(f"识别结果: {text}")
    else:
        print(f"测试文件不存在: {test_wav}")
