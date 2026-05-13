#!/usr/bin/env python3
"""
文本转语音模块 - 基于 Piper TTS（源码集成）
功能：将文本转为 WAV 音频文件
特点：
  - 源码集成（非命令行调用）
  - 模型轻量(~63MB)，推理极快
  - 纯 CPU 运行，零显存占用
  - C++ 共享库 + ctypes 调用

编译方法（在 /opt/piper-src 目录）：
    mkdir build && cd build
    cmake -DCMAKE_CXX_FLAGS="-fPIC" ..
    make -j$(nproc) piper_tts

依赖：
    - Piper 源码：https://github.com/rhasspy/piper
    - CMake >= 3.13
    - g++ >= 9.0
"""
import ctypes
import os

from config import (
    PIPER_LIB,
    PIPER_MODEL_PATH,
    PIPER_MODEL_CONFIG,
    PIPER_ESPEAK_DATA,
    PIPER_ONNX_PATH,
)

# 兼容：使用 config.py 中的变量
MODEL_PATH = PIPER_MODEL_PATH
MODEL_CONFIG_PATH = PIPER_MODEL_CONFIG
ESPEAK_DATA_PATH = PIPER_ESPEAK_DATA

# ctypes 接口
_lib = None
_voice = None


def _load_library() -> ctypes.CDLL:
    """加载 Piper TTS 共享库"""
    global _lib
    if _lib is not None:
        return _lib

    if not os.path.exists(PIPER_LIB):
        raise FileNotFoundError(
            f"Piper 共享库不存在: {PIPER_LIB}\n"
            f"请先编译: cd {PIPER_SRC_DIR} && mkdir build && cd build && cmake .. && make piper_tts"
        )

    _lib = ctypes.CDLL(PIPER_LIB)

    # 定义函数签名
    _lib.piper_initialize.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    _lib.piper_initialize.restype = ctypes.c_int

    _lib.piper_load_voice.argtypes = [
        ctypes.c_char_p,  # model_path
        ctypes.c_char_p,  # model_config_path
        ctypes.c_int64,   # speaker_id
        ctypes.c_int,     # use_cuda
    ]
    _lib.piper_load_voice.restype = ctypes.c_void_p

    _lib.piper_synthesize_to_file.argtypes = [
        ctypes.c_void_p,  # voice
        ctypes.c_char_p,  # text
        ctypes.c_char_p,  # output_path
    ]
    _lib.piper_synthesize_to_file.restype = ctypes.c_int

    _lib.piper_free_voice.argtypes = [ctypes.c_void_p]
    _lib.piper_free_voice.restype = None

    _lib.piper_terminate.argtypes = []
    _lib.piper_terminate.restype = None

    return _lib


def _initialize():
    """初始化 Piper TTS 引擎"""
    global _voice
    if _voice is not None:
        return

    lib = _load_library()

    # 初始化引擎
    espeak_path = ESPEAK_DATA_PATH.encode("utf-8")
    result = lib.piper_initialize(espeak_path, None)
    if result != 0:
        raise RuntimeError("Piper 初始化失败")

    # 加载语音模型
    if not os.path.exists(MODEL_PATH):
        raise FileNotFoundError(f"模型文件不存在: {MODEL_PATH}")
    if not os.path.exists(MODEL_CONFIG_PATH):
        raise FileNotFoundError(f"模型配置不存在: {MODEL_CONFIG_PATH}")

    _voice = lib.piper_load_voice(
        MODEL_PATH.encode("utf-8"),
        MODEL_CONFIG_PATH.encode("utf-8"),
        -1,  # 默认说话人
        0,   # 不使用 CUDA
    )
    if not _voice:
        raise RuntimeError("语音模型加载失败")


def text_to_speech(text: str, output_path: str = None) -> str:
    """
    将文本转为语音

    Args:
        text: 要转换的文本
        output_path: 输出文件路径，默认 /tmp/piper_tts_<timestamp>.wav

    Returns:
        生成的音频文件路径，失败抛出异常
    """
    if not text or not text.strip():
        return ""

    _initialize()

    if output_path is None:
        import time
        output_path = f"/tmp/piper_tts_{int(time.time())}.wav"

    lib = _load_library()
    result = lib.piper_synthesize_to_file(
        _voice,
        text.strip().encode("utf-8"),
        output_path.encode("utf-8"),
    )

    if result != 0:
        raise RuntimeError("语音合成失败")

    if os.path.exists(output_path):
        return output_path
    return ""


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


def cleanup():
    """释放资源（进程退出时调用）"""
    global _voice
    if _voice is not None and _lib is not None:
        _lib.piper_free_voice(_voice)
        _voice = None
    if _lib is not None:
        _lib.piper_terminate()


if __name__ == "__main__":
    import time

    print("=== Piper TTS 源码集成测试 ===")

    test_texts = [
        "你好，我是钉钉机器人助手。",
        "今天天气不错，适合出去散步。",
        "源码集成测试成功。",
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

    cleanup()
    print("\n资源已释放")
