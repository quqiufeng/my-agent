#!/usr/bin/env python3
"""
API 模块 - 统一调用多种大模型 API
==================================
支持: SiliconFlow, LM Studio, llama.cpp, MiniMax

使用方式:
1. 专有调用:
   - call_minimax("问题")
   - call_silicon("问题", model="deepseek-ai/DeepSeek-V3")
   - call_lmstudio("问题", model="qwen3-9b")
   - call_llama_cpp("问题")

2. 统一调用:
   - chat("问题", source="minimax")
   - chat("问题", source="silicon", model="deepseek-ai/DeepSeek-V3")
"""

import os
import requests
from typing import List, Dict, Optional, Literal, Union
from dataclasses import dataclass

# ==================== 配置 ====================

# API 来源枚举
ApiSource = Literal["silicon", "lmstudio", "llama", "ollama", "minimax"]

# 默认配置
DEFAULT_SOURCE: ApiSource = "minimax"

# 各 API 基础配置
CONFIG = {
    "silicon": {
        "base_url": "https://api.siliconflow.cn/v1",
        "key_env": "SILICON_API_KEY",
        "default_model": "Pro/zai-org/GLM-5",
    },
    "lmstudio": {
        "base_url": "http://192.168.124.3:11434/v1",
        "key_env": None,  # 本地无需 Key
        "default_model": "qwen3-9b",
    },
    "llama": {
        "base_url": "http://localhost:11434",
        "key_env": None,
        "default_model": "qwen3.5-9b",
    },
    "ollama": {
        "base_url": "http://localhost:11434/v1",
        "key_env": None,
        "default_model": "qwen2.5:7b",
    },
    "minimax": {
        "base_url": "https://api.minimaxi.com/v1/chat/completions",
        "key_env": "MINIMAX_API_KEY",
        "default_model": "MiniMax-M2.5",
    },
}

# 常用模型映射表
MODELS = {
    # SiliconFlow 云端模型
    "deepseek-v3": "deepseek-ai/DeepSeek-V3",
    "deepseek-v3.2": "deepseek-ai/DeepSeek-V3.2",
    "deepseek-r1": "deepseek-ai/DeepSeek-R1",
    "deepseek-r1-32b": "deepseek-ai/DeepSeek-R1-Distill-Qwen-32B",
    "deepseek-r1-14b": "deepseek-ai/DeepSeek-R1-Distill-Qwen-14B",
    "deepseek-r1-7b": "deepseek-ai/DeepSeek-R1-Distill-Qwen-7B",
    "qwen3-8b": "Qwen/Qwen3-8B",
    "qwen3-14b": "Qwen/Qwen3-14B",
    "qwen3-32b": "Qwen/Qwen3-32B",
    "qwen2.5-7b": "Qwen/Qwen2.5-7B-Instruct",
    "qwen2.5-14b": "Qwen/Qwen2.5-14B-Instruct",
    "qwen2.5-32b": "Qwen/Qwen2.5-32B-Instruct",
    "kimi-k2.5": "Pro/moonshotai/Kimi-K2.5",
    "glm-4.7": "Pro/zai-org/GLM-4.7",
    "llama-3.1-8b": "meta-llama/Llama-3.1-8B-Instruct",
    # LM Studio 本地模型
    "qwen3-9b": "qwen3-9b",
    "qwen2.5-8b": "qwen2.5-8b",
    "llama-3-8b": "llama-3-8b",
    "mistral-7b": "mistral-7b",
    # MiniMax
    "minimax": "MiniMax-M2.5",
}

# 全局 API Key 缓存
_API_KEYS: Dict[str, str] = {}


# ==================== 内部函数 ====================


def _get_api_key(source: ApiSource) -> str:
    """获取指定来源的 API Key"""
    global _API_KEYS

    if source in _API_KEYS and _API_KEYS[source]:
        return _API_KEYS[source]

    key_env = CONFIG[source].get("key_env")
    if not key_env:
        _API_KEYS[source] = ""
        return ""

    # 从环境变量获取
    api_key = os.environ.get(key_env)
    if api_key:
        _API_KEYS[source] = api_key
        return api_key

    # 从 .env 文件获取
    env_path = os.path.join(os.path.dirname(__file__), ".env")
    if os.path.exists(env_path):
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line.startswith(f"{key_env}="):
                    api_key = line.split("=", 1)[1].strip()
                    _API_KEYS[source] = api_key
                    return api_key

    return ""


def _get_base_url(source: ApiSource) -> str:
    """获取指定来源的 API 基础 URL"""
    return CONFIG[source]["base_url"]


def _get_default_model(source: ApiSource) -> str:
    """获取指定来源的默认模型"""
    return CONFIG[source]["default_model"]


def _normalize_model(model: str, source: ApiSource) -> str:
    """标准化模型名称"""
    if model in MODELS:
        return MODELS[model]
    return model


# ==================== 专有调用函数 ====================


def call_minimax(
    prompt: str,
    model: str = "MiniMax-M2.5",
    temperature: float = 0.7,
    max_tokens: int = 8192,
) -> str:
    """调用 MiniMax API"""
    api_key = _get_api_key("minimax")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }

    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": temperature,
    }

    response = requests.post(
        _get_base_url("minimax"), headers=headers, json=payload, timeout=180
    )
    result = response.json()
    return result["choices"][0]["message"]["content"]


def call_silicon(
    prompt: str,
    model: str = "deepseek-ai/DeepSeek-V3",
    temperature: float = 0.7,
    max_tokens: int = 4096,
) -> str:
    """调用 SiliconFlow API"""
    api_key = _get_api_key("silicon")
    model = _normalize_model(model, "silicon")

    return chat(
        messages=[{"role": "user", "content": prompt}],
        model=model,
        source="silicon",
        temperature=temperature,
        max_tokens=max_tokens,
    )


def call_lmstudio(
    prompt: str,
    model: str = "qwen3-9b",
    temperature: float = 0.7,
    max_tokens: int = 4096,
) -> str:
    """调用 LM Studio 本地 API"""
    model = _normalize_model(model, "lmstudio")

    return chat(
        messages=[{"role": "user", "content": prompt}],
        model=model,
        source="lmstudio",
        temperature=temperature,
        max_tokens=max_tokens,
    )


def call_llama_cpp(
    prompt: str,
    model: str = "llama-3.1-8b",
    temperature: float = 0.7,
    max_tokens: int = 4096,
) -> str:
    """调用 llama.cpp 兼容 API (llama.cpp server)"""
    model = _normalize_model(model, "llama")

    return chat(
        messages=[{"role": "user", "content": prompt}],
        model=model,
        source="llama",
        temperature=temperature,
        max_tokens=max_tokens,
    )


def call_ollama(
    prompt: str,
    model: str = "qwen2.5:7b",
    temperature: float = 0.7,
    max_tokens: int = 4096,
) -> str:
    """调用 Ollama 本地 API"""
    return chat(
        messages=[{"role": "user", "content": prompt}],
        model=model,
        source="ollama",
        temperature=temperature,
        max_tokens=max_tokens,
    )


# ==================== 统一调用函数 ====================


def chat(
    messages: List[Dict[str, str]],
    model: Optional[str] = None,
    source: ApiSource = DEFAULT_SOURCE,
    temperature: float = 0.7,
    max_tokens: int = 4096,
    tools: Optional[List[Dict]] = None,
    **kwargs,
) -> str:
    """
    统一的大模型对话接口

    Args:
        messages: 对话消息列表
        model: 模型名称 (支持简称或完整 ID)
        source: API 来源 (silicon/lmstudio/llama/minimax)
        temperature: 温度参数
        max_tokens: 最大 token 数
        tools: 工具列表

    Returns:
        模型回复文本
    """
    api_key = _get_api_key(source)
    model = model or _get_default_model(source)
    model = _normalize_model(model, source)

    url = _get_base_url(source)
    if source != "minimax":
        url = url.rstrip("/") + "/chat/completions"

    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    payload = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }

    if tools:
        payload["tools"] = tools

    payload.update(kwargs)

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=120)
        response.raise_for_status()
        result = response.json()
        return result["choices"][0]["message"]["content"]
    except requests.exceptions.Timeout:
        raise TimeoutError("API 请求超时")
    except requests.exceptions.RequestException as e:
        raise ConnectionError(f"API 请求失败: {e}")
    except (KeyError, IndexError) as e:
        raise ValueError(f"API 响应解析失败: {e}")


def chat_with_json(
    messages: List[Dict[str, str]],
    model: Optional[str] = None,
    source: ApiSource = DEFAULT_SOURCE,
    **kwargs,
) -> Dict:
    """
    统一的大模型对话接口，返回完整 JSON 响应

    Args:
        messages: 对话消息列表
        model: 模型名称
        source: API 来源
        **kwargs: 其他 API 参数

    Returns:
        完整 API 响应 (dict)
    """
    api_key = _get_api_key(source)
    model = model or _get_default_model(source)
    model = _normalize_model(model, source)

    url = _get_base_url(source)
    if source != "minimax":
        url = url.rstrip("/") + "/chat/completions"

    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    payload = {
        "model": model,
        "messages": messages,
    }
    payload.update(kwargs)

    response = requests.post(url, headers=headers, json=payload, timeout=120)
    response.raise_for_status()
    return response.json()


def get_models(source: ApiSource = DEFAULT_SOURCE) -> List[str]:
    """获取指定来源的可用模型列表"""
    api_key = _get_api_key(source)
    url = _get_base_url(source).rstrip("/") + "/models"

    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    response = requests.get(url, headers=headers)
    response.raise_for_status()

    data = response.json()
    return [m["id"] for m in data.get("data", [])]


# ==================== 便捷别名 ====================

# 兼容旧代码
DEFAULT_MODEL = _get_default_model(DEFAULT_SOURCE)
SILICON_BASE_URL = CONFIG["silicon"]["base_url"]
LM_STUDIO_BASE_URL = CONFIG["lmstudio"]["base_url"]
MINIMAX_BASE_URL = CONFIG["minimax"]["base_url"]


def get_api_key(source: ApiSource = DEFAULT_SOURCE) -> str:
    """获取 API Key (兼容旧代码)"""
    return _get_api_key(source)


def get_model_url(source: ApiSource = DEFAULT_SOURCE) -> str:
    """获取 API 基础 URL (兼容旧代码)"""
    return _get_base_url(source)


def get_api_url(
    endpoint: str = "chat/completions", source: ApiSource = DEFAULT_SOURCE
) -> str:
    """获取完整 API URL (兼容旧代码)"""
    base = _get_base_url(source)
    return base.rstrip("/") + "/" + endpoint


def update_models():
    """从 API 获取模型列表 (兼容旧代码)"""
    global MODELS
    try:
        models = get_models()
        for m in models:
            short = m.split("/")[-1].lower().replace("-", "_")
            MODELS[short] = m
        print(f"已更新模型列表，共 {len(MODELS)} 个模型")
    except Exception as e:
        print(f"获取模型列表失败: {e}")


# ==================== 测试 ====================

if __name__ == "__main__":
    print("=" * 50)
    print("API 模块测试")
    print("=" * 50)
    print(f"默认来源: {DEFAULT_SOURCE}")
    print(f"默认模型: {DEFAULT_MODEL}")
    print()

    # 测试各来源
    test_sources = ["lmstudio", "silicon", "llama", "minimax"]

    for source in test_sources:
        print(f"测试 {source}...")
        try:
            result = chat(
                [{"role": "user", "content": "你好"}],
                source=source,
                max_tokens=50,
            )
            print(f"  ✓ 成功: {result[:50]}...")
        except Exception as e:
            print(f"  ✗ 失败: {e}")
