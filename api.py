#!/usr/bin/env python3
"""
API 模块 - 调用大模型 API
支持 SiliconFlow 和本地 LM Studio (OpenAI 兼容 API)
"""

import os
import requests
from typing import List, Dict, Optional, Literal

# SiliconFlow API 配置
SILICON_BASE_URL = "https://api.siliconflow.cn/v1"

# LM Studio 本地 API 配置 (可配置 IP)
DEFAULT_API_SOURCE = "lmstudio"  # Use local LM Studio or SiliconFlow

LM_STUDIO_BASE_URL = (
    "http://198.18.0.1:11434/v1"  # OpenAI 兼容 API，根据实际局域网地址修改
)

# 默认模型（LM Studio）
DEFAULT_MODEL = "qwen3.5-9b"

# 常用模型列表（可动态更新）
MODELS = {
    # LM Studio 本地模型
    "lmstudio-qwen3.5-9b": DEFAULT_MODEL,
    "deepseek-v3": "deepseek-ai/DeepSeek-V3",
    "deepseek-v3.2": "deepseek-ai/DeepSeek-V3.2",
    "deepseek-r1": "deepseek-ai/DeepSeek-R1",
    "deepseek-r1-distill-qwen-32b": "deepseek-ai/DeepSeek-R1-Distill-Qwen-32B",
    "deepseek-r1-distill-qwen-14b": "deepseek-ai/DeepSeek-R1-Distill-Qwen-14B",
    "deepseek-r1-distill-qwen-7b": "deepseek-ai/DeepSeek-R1-Distill-Qwen-7B",
    # Qwen 系列
    "qwen3-8b": "Qwen/Qwen3-8B",
    "qwen3-14b": "Qwen/Qwen3-14B",
    "qwen3-32b": "Qwen/Qwen3-32B",
    "qwen3-vl-32b": "Qwen/Qwen3-VL-32B-Instruct",
    "qwen2.5-7b": "Qwen/Qwen2.5-7B-Instruct",
    "qwen2.5-14b": "Qwen/Qwen2.5-14B-Instruct",
    "qwen2.5-32b": "Qwen/Qwen2.5-32B-Instruct",
    "qwen2.5-coder-7b": "Qwen/Qwen2.5-Coder-7B-Instruct",
    "qwen2.5-coder-32b": "Qwen/Qwen2.5-Coder-32B-Instruct",
    "qwen2-vl-72b": "Qwen/Qwen2-VL-72B-Instruct",
    "qwen2.5-vl-7b": "Qwen/Qwen2.5-VL-7B-Instruct",
    "qwq-32b": "Qwen/QwQ-32B",
    # Kimi 系列
    "kimi-k2.5": "Pro/moonshotai/Kimi-K2.5",
    "kimi-k2-thinking": "moonshotai/Kimi-K2-Thinking",
    # GLM 系列
    "glm-4.7": "Pro/zai-org/GLM-4.7",
    "glm-4.6": "zai-org/GLM-4.6",
    "glm-4.6v": "zai-org/GLM-4.6V",
    "glm-4.5v": "zai-org/GLM-4.5V",
    "glm-5": "Pro/zai-org/GLM-5",
    # Step 系列
    "step-3.5-flash": "stepfun-ai/Step-3.5-Flash",
    # 其他
    "llama-3.1-8b": "meta-llama/Llama-3.1-8B-Instruct",
    "internlm2.5-7b": "internlm/internlm2_5-7b-chat",
}

# 默认模型
DEFAULT_MODEL = MODELS.get("lmstudio-qwen3.5-9b", MODELS["kimi-k2.5"])


def get_api_key(source: Literal["silicon", "lmstudio"] = DEFAULT_API_SOURCE) -> str:
    """从环境变量或 .env 文件获取 API Key"""
    if source == "silicon":
        # 优先从环境变量读取
        api_key = os.environ.get("SILICON_API_KEY")
        if api_key:
            return api_key

        # 其次从 .env 文件读取
        env_path = os.path.join(os.path.dirname(__file__), ".env")
        if os.path.exists(env_path):
            with open(env_path) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("SILICON_API_KEY="):
                        return line.split("=", 1)[1].strip()

        raise ValueError("请设置 SILICON_API_KEY 环境变量或在 .env 文件中配置")
    else:
        # LM Studio 不需要 API Key，直接返回空字符串
        return ""


def get_model_url(source=None):
    """Get model URL based on source"""
    if source is None:
        source = DEFAULT_API_SOURCE
    
    return LM_STUDIO_BASE_URL if source == "lmstudio" else SILICON_BASE_URL


def get_api_url(endpoint='chat/completions', source=None, api_base=''):
    """
    Get full API URL with endpoint.
    
    Args:
        endpoint: API endpoint path (e.g., 'chat/completions')
        source: API source ('lmstudio' or None)
        api_base: Base URL for non-lmstudio APIs
    
    Returns:
        Full API URL with endpoint
    """
    if source is None:
        source = DEFAULT_API_SOURCE
        
    # lmstudio needs complete endpoint path, but LM_STUDIO_BASE_URL already ends with /v1
    if source == 'lmstudio':
        return LM_STUDIO_BASE_URL.rstrip('/') + '/' + endpoint
    
    # For siliconflow and others, use api_base + endpoint
    if not api_base:
        api_base = get_model_url(source)
    return api_base.rstrip('/') + '/' + endpoint


def get_models() -> Dict[str, str]:
    """
    从 API 获取模型列表

    Returns:
        模型名字典 {简称：模型 ID}
    """
    api_key = get_api_key(source=DEFAULT_API_SOURCE)
    url = get_model_url()

    headers = {"Authorization": f"Bearer {api_key}"}

    response = requests.get(url, headers=headers)
    response.raise_for_status()

    data = response.json()
    new_models = {}

    for model in data["data"]:
        model_id = model["id"]
        # 提取简称（取最后部分作为 key）
        short_name = model_id.split("/")[-1].lower().replace("-", "_")
        new_models[short_name] = model_id

    return new_models


def update_models():
    """从 API 获取模型列表并更新 MODELS"""
    global MODELS
    try:
        api_models = get_models()
        MODELS.update(api_models)
        print(f"已更新模型列表，共 {len(MODELS)} 个模型")
    except Exception as e:
        print(f"获取模型列表失败: {e}")


def chat(
    messages: List[Dict[str, str]],
    model: str = DEFAULT_MODEL,
    temperature: float = 0.7,
    max_tokens: int = 4096,
    tools: Optional[List[Dict]] = None,
    **kwargs,
) -> str:
    """
    调用大模型 API，返回文本内容
    """
    api_key = get_api_key()

    url = get_api_url()

    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}

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
    messages: List[Dict[str, str]], model: str = DEFAULT_MODEL, endpoint='chat/completions', **kwargs
) -> Dict:
    """
    调用大模型 API，返回完整 JSON 响应
    
    Args:
        messages: Prompt messages (ChatML format)
        model: Model name/ID
        endpoint: API endpoint path (default 'chat/completions')
        **kwargs: Additional parameters to pass to API
    
    Returns:
        Full API response as dict
    """
    api_key = get_api_key()
    
    # lmstudio doesn't require API key, use full endpoint path
    if DEFAULT_API_SOURCE == 'lmstudio':
        url = LM_STUDIO_BASE_URL.rstrip('/') + '/' + endpoint.replace('/v1', '')
        headers = {"Content-Type": "application/json"}
    else:
        url = get_api_url(endpoint)
        headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}

    payload = {
        "model": model,
        "messages": messages,
    }
    payload.update(kwargs)

    response = requests.post(url, headers=headers, json=payload, timeout=120)
    response.raise_for_status()

    return response.json()


if __name__ == "__main__":
    # 测试
    print("SiliconFlow API 测试")
    print(f"默认模型: {DEFAULT_MODEL}")

    # 尝试更新模型列表
    print("\n获取模型列表...")
    update_models()

    print("\n可用模型:")
    for k, v in MODELS.items():
        print(f"  {k}: {v}")

    # 测试对话
    print("\n测试对话...")
    messages = [
        {"role": "system", "content": "你是一个有用的助手"},
        {"role": "user", "content": "你好，用一句话介绍自己"},
    ]

    try:
        response = chat(messages)
        print(f"\n响应: {response[:200]}")
    except Exception as e:
        print(f"错误: {e}")
