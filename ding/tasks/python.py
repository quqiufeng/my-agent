"""
Python 代码执行任务
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult
from executor import Executor
from config import Config

SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class PythonTask(BaseTask):
    """执行 Python 代码"""
    task_type = "python"
    
    def __init__(self):
        self.executor = Executor()
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        code = content.get("code", "")
        if not code:
            return TaskResult.err("未提供代码").to_dict()
        
        # 注入 SCRIPT_DIR 到子进程
        code = f"import os\nSCRIPT_DIR = '{SCRIPT_DIR}'\nimport sys\nsys.path.insert(0, SCRIPT_DIR)\n" + code
        
        if Config.API_KEY:
            code = code.replace('YOUR_API_KEY', Config.API_KEY)
        
        exec_result = self.executor.execute_python_subprocess(code)
        return TaskResult(
            success=exec_result.get("success", False),
            stdout=exec_result.get("stdout", ""),
            stderr=exec_result.get("stderr", "")
        ).to_dict()
