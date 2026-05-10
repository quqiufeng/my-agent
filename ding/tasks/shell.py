"""
Shell 命令任务
"""
import sys
import os
import re
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult
from executor import Executor
from config import FORBIDDEN_PATTERNS


class ShellTask(BaseTask):
    """执行 Shell 命令"""
    task_type = "shell"
    
    def __init__(self):
        self.executor = Executor()
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        raw = content.get("raw", "")
        # 去掉 #shell 前缀
        row = raw.replace("#shell", "").strip()
            
        if not row:
            return TaskResult.err("未提供命令").to_dict()
        
        # 检查危险命令
        for pattern in FORBIDDEN_PATTERNS:
            if re.search(pattern, row, re.IGNORECASE):
                return TaskResult.err(f"非法操作: 命令包含禁止模式 {pattern}").to_dict()
        
        exec_result = self.executor.execute(row)
        return TaskResult(
            success=exec_result.get("success", False),
            stdout=exec_result.get("stdout", ""),
            stderr=exec_result.get("stderr", "")
        ).to_dict()
