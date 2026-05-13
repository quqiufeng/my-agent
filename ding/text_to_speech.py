#!/usr/bin/env python3
"""
文本转语音模块 - 基于 Piper TTS
功能：将文本转为 WAV 音频文件
特点：模型轻量(~63MB)，推理极快，纯 CPU 运行
"""
import os
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)

# Piper 配置
PIPER_DIR = os.path.join(PROJECT_DIR, "bin", "piper")
PIPER_BIN = os.path.join(PIPER_DIR, "piper")
MODEL_PATH = os.path.join(PROJECT_DIR, "models", "piper", "zh_CN-huayan-medium.onnx")


def text_to_speech(text: str, output_path: str = None) -> str:
    """
    将文本转为语音

    Args:
        text: 要转换的文本
        output_path: 输出文件路径，默认 /tmp/piper_tts_<timestamp>.wav

    Returns:
        生成的音频文件路径，失败返回空字符串
    """
    if not text or not text.strip():
        return ""

    if not os.path.exists(PIPER_BIN):
        raise FileNotFoundError(f"Piper 可执行文件不存在: {PIPER_BIN}")
    if not os.path.exists(MODEL_PATH):
        raise FileNotFoundError(f"Piper 模型不存在: {MODEL_PATH}")

    if output_path is None:
        import time
        output_path = f"/tmp/piper_tts_{int(time.time())}.wav"

    try:
        # 使用 pipe 输入文本
        cmd = [
            PIPER_BIN,
            "--model", MODEL_PATH,
            "--output_file", output_path,
        ]

        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = PIPER_DIR

        result = subprocess.run(
            cmd,
            input=text.strip(),
            capture_output=True,
            text=True,
            timeout=30,
            env=env,
            cwd=PIPER_DIR,
        )

        if result.returncode != 0:
            raise RuntimeError(f"Piper 合成失败: {result.stderr}")

        if os.path.exists(output_path):
            return output_path
        return ""

    except subprocess.TimeoutExpired:
        raise RuntimeError("Piper 合成超时")
    except Exception as e:
        raise RuntimeError(f"Piper 合成异常: {e}")


def text_to_speech_file(text: str, output_path: str) -> bool:
    """
    将文本转为语音并保存到指定文件

    Args:
        text: 要转换的文本
        output_path: 输出文件路径

    Returns:
        是否成功
    """
    try:
        path = text_to_speech(text, output_path)
        return bool(path)
    except Exception:
        return False


if __name__ == "__main__":
    import time

    print("=== Piper TTS 测试 ===")

    test_texts = [
        "你好，我是钉钉机器人助手。",
        "今天天气不错，适合出去散步。",
        "SenseVoice 语音识别模型加载成功。",
    ]

    for i, text in enumerate(test_texts):
        print(f"\n测试 {i+1}: {text}")
        t0 = time.time()
        try:
            output = text_to_speech(text, f"/tmp/piper_test_{i}.wav")
            elapsed = time.time() - t0
            if output:
                size = os.path.getsize(output)
                print(f"  成功: {output} ({size} bytes, {elapsed:.2f}s)")
            else:
                print("  失败")
        except Exception as e:
            print(f"  错误: {e}")
