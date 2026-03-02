#!/usr/bin/env python3
"""
API 模块 - 调用大模型 API
仅支持 SiliconFlow
"""

import os
import requests
from typing import List, Dict, Optional

# SiliconFlow API 配置
BASE_URL = "https://api.siliconflow.cn/v1"

# 常用模型列表（可动态更新）
MODELS = {
    # DeepSeek 系列
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
DEFAULT_MODEL = MODELS["kimi-k2.5"]


def get_api_key() -> str:
    """从环境变量或 .env 文件获取 API Key"""
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


def get_models() -> Dict[str, str]:
    """
    从 API 获取模型列表

    Returns:
        模型名字典 {简称: 模型ID}
    """
    api_key = get_api_key()
    url = f"{BASE_URL}/models"

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

    url = f"{BASE_URL}/chat/completions"

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
    messages: List[Dict[str, str]], model: str = DEFAULT_MODEL, **kwargs
) -> Dict:
    """
    调用大模型 API，返回完整 JSON 响应
    """
    api_key = get_api_key()

    url = f"{BASE_URL}/chat/completions"

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
