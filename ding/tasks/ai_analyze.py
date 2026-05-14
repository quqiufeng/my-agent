"""
AI 分析任务 - 本地图片分析（JoyCaption）
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult
from logger import task_logger as logger
import dingtalk

# 导入本地图片分析模块
try:
    from image_analyzer import analyze_image
    LOCAL_IMAGE_ANALYSIS_AVAILABLE = True
except ImportError as e:
    logger.warning(f"本地图片分析模块未加载: {e}")
    LOCAL_IMAGE_ANALYSIS_AVAILABLE = False


class AIAnalyzeTask(BaseTask):
    """AI 图片分析任务 - 使用本地 JoyCaption 模型"""
    task_type = "ai_analyze"
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        # 图片消息
        download_code = content.get("download_code", "")
        robot_code = content.get("robot_code", "")
        prompt = content.get("prompt", None)  # 使用默认提示词
        
        if not download_code or not robot_code:
            return TaskResult.err("未提供图片").to_dict()
        
        try:
            dt = dingtalk.get_dingtalk()
            image_path = dt.download_file(download_code, robot_code)
        except Exception as e:
            logger.error(f"图片下载失败: {e}")
            return TaskResult.err("图片下载失败").to_dict()
        
        if not image_path:
            return TaskResult.err("图片下载失败").to_dict()
        
        # 使用本地模型分析
        if LOCAL_IMAGE_ANALYSIS_AVAILABLE:
            try:
                logger.info(f"[AIAnalyze] 使用本地 JoyCaption 分析图片: {image_path}")
                result = analyze_image(image_path, prompt=prompt)
                return TaskResult(
                    success=True,
                    stdout=result
                ).to_dict()
            except Exception as e:
                logger.error(f"[AIAnalyze] 本地分析失败: {e}")
                return TaskResult.err(f"图片分析失败: {e}").to_dict()
        else:
            return TaskResult.err("本地图片分析模块未加载").to_dict()
