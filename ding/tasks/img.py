"""
图像生成任务 - 调用本地 stable-diffusion.cpp 生成图片

用法:
    #img 一只可爱的猫坐在窗台上
    #img 夕阳下的海边 1280 720

参数:
    - 提示词（必填）
    - 宽度（可选，默认1280）
    - 高度（可选，默认720）
"""
import sys
import os
import re
import subprocess
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult
from logger import task_logger as logger
import dingtalk


SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG_SH = "/home/dministrator/my-agent/img.sh"
OUTPUT_DIR = os.path.expanduser("~")


class ImgTask(BaseTask):
    """本地图像生成任务 - 调用 img.sh"""
    task_type = "img"
    
    def __init__(self):
        os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        raw = content.get("raw", "")
        # 去掉 #img 前缀
        args_str = raw.replace("#img", "").strip()
        
        if not args_str:
            return TaskResult.err("请提供提示词，例如: #img 一只可爱的猫").to_dict()
        
        # 默认尺寸
        width = "1280"
        height = "720"
        prompt = args_str
        
        # ========== 智能尺寸解析 ==========
        # 1. 先尝试匹配 prompt 中的 WxH 格式（如 120x120, 512x512, 1920x1080）
        size_match = re.search(r'(\d{2,4})\s*[xX×]\s*(\d{2,4})', args_str)
        if size_match:
            w, h = size_match.group(1), size_match.group(2)
            # 验证合理性：16~2048
            if 16 <= int(w) <= 2048 and 16 <= int(h) <= 2048:
                width, height = w, h
                # 移除尺寸描述，保留其余 prompt
                prompt = re.sub(r'\s*' + re.escape(size_match.group(0)) + r'\s*', ' ', args_str).strip()
                # 同时移除常见的尺寸修饰词
                prompt = re.sub(r'\s*(pixels?|px|resolution|尺寸|大小|宽高)\s*', ' ', prompt, flags=re.I).strip()
        else:
            # 2.  fallback：检查最后两个纯数字
            parts = args_str.split()
            if len(parts) >= 3:
                if parts[-1].isdigit() and parts[-2].isdigit():
                    height = parts[-1]
                    width = parts[-2]
                    prompt = " ".join(parts[:-2])
            elif len(parts) == 2:
                if parts[-1].isdigit() and parts[-2].isdigit():
                    height = parts[-1]
                    width = parts[-2]
                    prompt = ""
                elif parts[-1].isdigit():
                    width = parts[-1]
                    prompt = parts[0]
        
        # 生成输出文件名
        timestamp = str(int(time.time()))
        output_file = os.path.join(OUTPUT_DIR, f"img_{timestamp}.png")
        
        # 构造命令
        cmd = [IMG_SH, prompt, output_file, width, height]
        
        logger.info(f"[ImgTask] 开始生成图片: prompt={prompt}, size={width}x{height}, output={output_file}")
        
        try:
            # 执行 img.sh（可能需要较长时间，设置大超时）
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300,  # 5分钟超时
                cwd=os.path.dirname(IMG_SH)
            )
            
            if result.returncode != 0:
                error_msg = result.stderr or "未知错误"
                logger.error(f"[ImgTask] img.sh 执行失败: {error_msg}")
                return TaskResult.err(f"图片生成失败: {error_msg[:500]}").to_dict()
            
            # 检查输出文件
            if not os.path.exists(output_file):
                return TaskResult.err("图片生成完成但未找到输出文件").to_dict()
            
            logger.info(f"[ImgTask] 图片生成成功: {output_file}")
            logger.info(f"[DEBUG] session_webhook={session_webhook}")
            
            # 如果提供了 session_webhook，上传并发送图片
            exec_responses = ""
            if session_webhook:
                try:
                    dt = dingtalk.get_dingtalk()
                    
                    # 读取图片内容
                    with open(output_file, "rb") as f:
                        image_content = f.read()
                    
                    # 上传到钉钉
                    media_id = dt.upload_media("image", file_content=image_content, filename="generated.png")
                    
                    if media_id:
                        # 发送 Markdown 图片消息（支持点击放大）
                        dt.send_markdown_image(session_webhook, media_id)
                        exec_responses = f"__MEDIA_ID__: {media_id}\n__LOCAL_IMAGE__: {output_file}"
                        logger.info(f"[ImgTask] 图片已通过 Markdown 发送到钉钉: media_id={media_id}")
                    else:
                        logger.error("[ImgTask] 上传图片到钉钉失败")
                        
                except Exception as e:
                    logger.error(f"[ImgTask] 发送图片失败: {e}")
            
            return TaskResult(
                success=True,
                stdout=f"图片生成成功: {output_file}",
                exec_responses=exec_responses
            ).to_dict()
            
        except subprocess.TimeoutExpired:
            logger.error("[ImgTask] 图片生成超时")
            return TaskResult.err("图片生成超时（超过5分钟）").to_dict()
        except Exception as e:
            logger.error(f"[ImgTask] 异常: {e}")
            return TaskResult.err(f"图片生成异常: {str(e)}").to_dict()
