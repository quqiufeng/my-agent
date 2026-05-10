"""
AI 分析任务 - 描述图片
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult
from ai import AI
from logger import task_logger as logger
import dingtalk


class AIAnalyzeTask(BaseTask):
    """AI 图片分析任务 - 描述图片内容"""
    task_type = "ai_analyze"
    
    def __init__(self):
        self.ai = AI()
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        # 图片消息
        download_code = content.get("download_code", "")
        robot_code = content.get("robot_code", "")
        prompt = content.get("prompt", "描述这张图片的内容")
        
        if download_code and robot_code:
            try:
                dt = dingtalk.get_dingtalk()
                image_url = dt.download_file(download_code, robot_code)
            except Exception as e:
                logger.error(f"图片下载失败: {e}")
                return TaskResult.err("图片下载失败").to_dict()
            
            if image_url:
                ai_result = self.ai.analyze_image(image_url, prompt)
                return TaskResult(
                    success=True,
                    stdout=ai_result.get("summary", "")
                ).to_dict()
            else:
                return TaskResult.err("图片下载失败").to_dict()
        
        return TaskResult.err("未提供图片").to_dict()
