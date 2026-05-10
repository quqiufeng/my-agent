"""
任务基础接口
所有任务处理器必须继承 BaseTask 并实现 execute 方法
"""
from abc import ABC, abstractmethod


class BaseTask(ABC):
    """任务处理器基类"""
    
    # 任务类型标识（子类必须定义）
    task_type = ""
    
    @abstractmethod
    def execute(self, content: dict, session_webhook=None) -> dict:
        """
        执行任务
        
        Args:
            content: 任务内容字典
            session_webhook: 钉钉会话 webhook（用于发送消息）
            
        Returns:
            dict: 执行结果，包含：
                - success: bool 是否成功
                - stdout: str 标准输出
                - stderr: str 错误输出
                - error: str 错误信息
        """
        pass
    
    def get_task_type(self) -> str:
        """获取任务类型"""
        return self.task_type


class TaskResult:
    """任务结果封装"""
    
    def __init__(self, success=False, stdout="", stderr="", error="", **kwargs):
        self.success = success
        self.stdout = stdout
        self.stderr = stderr
        self.error = error
        self.extra = kwargs
    
    def to_dict(self) -> dict:
        result = {
            "success": self.success,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "error": self.error,
        }
        result.update(self.extra)
        return result
    
    @classmethod
    def ok(cls, stdout="", **kwargs):
        return cls(success=True, stdout=stdout, **kwargs)
    
    @classmethod
    def err(cls, error="", **kwargs):
        return cls(success=False, error=error, **kwargs)
