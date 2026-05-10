"""Nano Banana 图像生成模块

用法:
    from nano_banana import generate_flashcard_background, make_flashcard_prompt
    
    # 1. 直接生成
    generate_flashcard_background(theme="你的提示词", filename="output.png")
    
    # 2. 用 helper 函数
    prompt = make_flashcard_prompt("Harry Potter 风格描述")
    generate_flashcard_background(theme=prompt, filename="output.png")
"""

import os
import base64
import re
import time
import requests
from pathlib import Path
from typing import Optional, Tuple
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.getenv("Nano_Banana_API_KEY", "")
BASE_URL = "https://api.laozhang.ai"


def download_image(url: str, output_dir: str, filename: str) -> str:
    """下载图片到本地"""
    filepath = os.path.join(output_dir, filename)
    response = requests.get(url)
    with open(filepath, "wb") as f:
        f.write(response.content)
    return filepath


def image_to_base64(filepath: str) -> Tuple[str, str]:
    """将本地图片转换为 base64"""
    with open(filepath, "rb") as f:
        data = base64.b64encode(f.read()).decode("utf-8")
    ext = Path(filepath).suffix.lower()
    mime_type = "image/jpeg" if ext in [".jpg", ".jpeg"] else f"image/{ext[1:]}" if ext else "image/png"
    return data, mime_type


def process_image_input(image_path: str, output_dir: str) -> str:
    """处理图片输入，支持本地路径和 URL"""
    if image_path.startswith("http://") or image_path.startswith("https://"):
        ext = image_path.split(".")[-1] if "." in image_path else "png"
        filename = f"input-{int(time.time())}.{ext}"
        return download_image(image_path, output_dir, filename)
    return image_path


def extract_base64_from_response(content: str) -> Optional[str]:
    """从响应中提取 base64 图片"""
    match = re.search(r'!\[.*?\]\((data:image/\w+;base64,.+?)\)', content)
    if match:
        data = match.group(1)
        base64_match = re.search(r'base64,(.+)', data)
        return base64_match.group(1) if base64_match else None
    direct_match = re.search(r'data:image/\w+;base64,(.+)', content)
    return direct_match.group(1) if direct_match else None


def save_image(base64_data: str, output_dir: str, prefix: str, filename: str = "") -> str:
    """保存图片到本地"""
    os.makedirs(output_dir, exist_ok=True)
    filepath = os.path.join(output_dir, filename) if filename else os.path.join(output_dir, f"{prefix}-{int(time.time())}.png")
    with open(filepath, "wb") as f:
        f.write(base64.b64decode(base64_data))
    return filepath


def nano(prompt: str = "", edit: bool = False, pro: bool = False, image: str = "",
         aspect: str = "1:1", size: str = "1K", output_dir: str = ".", filename: str = "") -> str:
    """Nano Banana 图像生成核心函数"""
    if not API_KEY:
        raise ValueError("请在 .env 文件中设置 Nano_Banana_API_KEY")
    if not prompt:
        raise ValueError("请输入图像描述文本")

    model = "gemini-3-pro-image-preview" if pro else "gemini-3.1-flash-image-preview"
    price = "$0.05/次" if pro else "$0.03/次"

    image_base64 = None
    image_mime_type = None
    if edit and image:
        image_path = process_image_input(image, output_dir)
        image_base64, image_mime_type = image_to_base64(image_path)

    if pro:
        parts = []
        if edit and image_base64 and image_mime_type:
            parts.append({"inline_data": {"mime_type": image_mime_type, "data": image_base64}})
        parts.append({"text": prompt})
        request_body = {
            "contents": [{"parts": parts}],
            "generationConfig": {
                "responseModalities": ["IMAGE"],
                "imageConfig": {"aspectRatio": aspect, "imageSize": size}
            }
        }
        url = f"{BASE_URL}/v1beta/models/gemini-3-pro-image-preview:generateContent"
        headers = {"Content-Type": "application/json", "x-goog-api-key": API_KEY}
    else:
        content = []
        if edit and image_base64 and image_mime_type:
            content.append({"type": "image_url", "image_url": {"url": f"data:{image_mime_type};base64,{image_base64}"}})
        content.insert(0, {"type": "text", "text": prompt})
        request_body = {"model": model, "messages": [{"role": "user", "content": content}]}
        url = f"{BASE_URL}/v1/chat/completions"
        headers = {"Content-Type": "application/json", "Authorization": f"Bearer {API_KEY}"}

    response = requests.post(url, headers=headers, json=request_body, timeout=180)
    data = response.json()
    if "error" in data:
        raise Exception(f"API Error: {data['error']['message']}")

    if pro:
        base64_data = data.get("candidates", [{}])[0].get("content", {}).get("parts", [{}])[0].get("inlineData", {}).get("data")
    else:
        content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
        base64_data = extract_base64_from_response(content)

    if not base64_data:
        raise Exception("未获取到图像内容")

    prefix = "nano"
    if pro and edit:
        prefix = "nano-pro-edit"
    elif pro:
        prefix = "nano-pro"
    elif edit:
        prefix = "nano-edit"

    filepath = save_image(base64_data, output_dir, prefix, filename)
    return f"图像已保存: {filepath} ({price})"


# ========== 单词卡片背景生成 ==========

def generate_flashcard_background(theme: str = "", style: str = "", aspect: str = "9:16",
                                  size: str = "1K", output_dir: str = ".", filename: str = "", pro: bool = True) -> str:
    """生成单词卡片背景
    
    参数:
        theme     - 提示词内容
        style     - 额外样式描述（可选）
        aspect    - 纵横比，默认 9:16 竖版
        size      - 分辨率，默认 1K
        output_dir- 输出目录
        filename  - 输出文件名
        pro       - 是否使用 Pro 模式（默认 True）
    
    示例:
        generate_flashcard_background(theme="Harry Potter", filename="card.png")
    """
    prompt = theme + (", " + style if style else "")
    print(f"[卡片背景生成] {theme[:30]}...")
    return nano(prompt=prompt, pro=pro, aspect=aspect, size=size, output_dir=output_dir, filename=filename)


def make_flashcard_prompt(prompt: str = "") -> str:
    """生成单词卡片背景提示词（自动添加留白布局）
    
    参数:
        prompt - 你想要的风格/元素描述
    
    返回:
        完整提示词（你的描述 + 固定留白布局）
    
    示例:
        prompt = make_flashcard_prompt("Harry Potter themed with Hogwarts castle")
    """
    if not prompt:
        raise ValueError("请输入提示词内容")
    
    # 固定的留白布局关键词
    blank_keywords = """Centered with a massive, solid, pure white rectangular box occupying the vast majority of the image. CRITICAL: The central rectangle must be 100% solid white and completely opaque, with NO illustrations, NO textures, and NO shadows inside. This central area MUST have four tiny, elegant golden ornate filigree corners. ABSOLUTELY NO TEXT, NO NUMBERS, NO PIXEL LABELS, NO MEASUREMENT LINES, NO RATIO NUMBERS, NO ANNOTATIONS. CLEAN WHITE INTERIOR ONLY. 8k, ultra-detailed."""
    
    return prompt + " " + blank_keywords
