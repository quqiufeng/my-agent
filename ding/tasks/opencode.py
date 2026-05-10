"""
OpenCode 任务
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult
from executor import Executor
from prompt import get_opencode_system_prompt
from logger import task_logger as logger


class OpenCodeTask(BaseTask):
    """调用 OpenCode AI 执行任务"""
    task_type = "opencode"
    
    def __init__(self):
        self.executor = Executor()
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        raw = content.get("raw", "")
        cmd = raw.replace("#opencode", "").strip()
        if not cmd:
            return TaskResult.err("未提供命令").to_dict()
        
        # 获取 OpenCode 系统提示词，用户需求在前，预设提示词在后
        system_prompt = get_opencode_system_prompt()
        full_message = f"#用户需求\n{cmd}\n#end\n\n{system_prompt}"
        logger.info(f"[OpenCode] full_message:\n{full_message}")
        
        exec_result = self.executor.execute_opencode(full_message)
        return TaskResult(
            success=exec_result.get("success", False),
            stdout=exec_result.get("stdout", ""),
            stderr=exec_result.get("stderr", "")
        ).to_dict()
