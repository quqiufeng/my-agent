#!/usr/bin/env python3
"""
JoyCaption 图片分析模块 - 本地模型封装（按需加载）

功能：
- 分析图片内容并生成详细描述
- 基于 llama.cpp + JoyCaption 模型
- 模型按需加载，推理完成后自动释放

用法：
    from image_analyzer import analyze_image
    result = analyze_image("/path/to/image.jpg")
    print(result)  # 输出详细描述
"""

import os
import sys
import ctypes
import tempfile
import subprocess

# 配置
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LLAMA_MTMD_CLI = os.path.expanduser("~/llama.cpp/build/bin/llama-mtmd-cli")
MODEL_PATH = os.path.expanduser("~/joycaption/Llama-Joycaption-Beta-One-Hf-Llava-Q4_K.gguf")
MMPROJ_PATH = os.path.expanduser("~/joycaption/llama-joycaption-beta-one-llava-mmproj-model-f16.gguf")


def _check_environment():
    """检查环境是否就绪"""
    errors = []
    
    if not os.path.exists(LLAMA_MTMD_CLI):
        errors.append(f"llama-mtmd-cli 未找到: {LLAMA_MTMD_CLI}")
    
    if not os.path.exists(MODEL_PATH):
        errors.append(f"模型未找到: {MODEL_PATH}")
    
    if not os.path.exists(MMPROJ_PATH):
        errors.append(f"mmproj 未找到: {MMPROJ_PATH}")
    
    if errors:
        raise EnvironmentError("\n".join(errors))


def analyze_image(image_path: str, prompt: str = None, max_tokens: int = 200) -> str:
    """
    分析图片内容（按需加载模型，推理后释放）
    
    Args:
        image_path: 图片文件路径（支持 jpg/png/webp 等）
        prompt: 提示词（可选，默认生成详细描述）
        max_tokens: 最大生成 token 数
    
    Returns:
        图片描述文本
    """
    _check_environment()
    
    if not os.path.exists(image_path):
        raise FileNotFoundError(f"图片不存在: {image_path}")
    
    # 默认提示词
    if prompt is None:
        prompt = "Describe this image in detail."
    
    # 构建命令
    cmd = [
        LLAMA_MTMD_CLI,
        "-m", MODEL_PATH,
        "--mmproj", MMPROJ_PATH,
        "--image", image_path,
        "-p", prompt,
        "-n", str(max_tokens),
        "--temp", "0.1",
    ]
    
    # 执行推理
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300  # 5 分钟超时
        )
        
        if result.returncode != 0:
            error_msg = result.stderr or "未知错误"
            raise RuntimeError(f"推理失败: {error_msg}")
        
        # 解析输出（提取生成内容）
        output = result.stdout
        
        # 去掉日志行，只保留生成内容
        lines = output.split('\n')
        content_lines = []
        for line in lines:
            # 跳过日志行
            if (line.startswith('llama_') or 
                line.startswith('load_') or 
                line.startswith('warmup') or 
                line.startswith('encoding') or 
                line.startswith('decoding') or 
                line.startswith('image decoded') or 
                line.startswith('common_') or 
                line.startswith('ggml_') or
                line.startswith('clip_') or
                line.startswith('CUDA Graph') or
                'ms/tok' in line or 
                'tokens per second' in line):
                continue
            if line.strip():
                content_lines.append(line)
        
        return '\n'.join(content_lines).strip()
        
    except subprocess.TimeoutExpired:
        raise RuntimeError("推理超时（5分钟）")
    except Exception as e:
        raise RuntimeError(f"推理异常: {e}")


def analyze_image_for_sd(image_path: str) -> str:
    """
    生成 Stable Diffusion 提示词（标签风格）
    
    Args:
        image_path: 图片文件路径
    
    Returns:
        SD 提示词（逗号分隔的标签）
    """
    prompt = "Generate a detailed Stable Diffusion prompt for this image. Use comma-separated tags and descriptors."
    return analyze_image(image_path, prompt=prompt, max_tokens=150)


def get_model_info() -> dict:
    """获取模型信息"""
    return {
        "model_path": MODEL_PATH,
        "mmproj_path": MMPROJ_PATH,
        "cli_path": LLAMA_MTMD_CLI,
        "model_exists": os.path.exists(MODEL_PATH),
        "mmproj_exists": os.path.exists(MMPROJ_PATH),
        "cli_exists": os.path.exists(LLAMA_MTMD_CLI),
        "model_size_mb": round(os.path.getsize(MODEL_PATH) / 1024 / 1024, 1) if os.path.exists(MODEL_PATH) else 0,
        "mmproj_size_mb": round(os.path.getsize(MMPROJ_PATH) / 1024 / 1024, 1) if os.path.exists(MMPROJ_PATH) else 0,
    }


if __name__ == "__main__":
    # 测试
    import sys
    
    if len(sys.argv) < 2:
        print("用法: python image_analyzer.py <图片路径>")
        sys.exit(1)
    
    image_path = sys.argv[1]
    print(f"分析图片: {image_path}")
    print("=" * 50)
    
    try:
        result = analyze_image(image_path)
        print(result)
    except Exception as e:
        print(f"错误: {e}")
        sys.exit(1)
