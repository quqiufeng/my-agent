"""
任务注册表
负责动态加载和管理任务处理器
"""
import os
import importlib
import logging
from typing import Dict, Type, Optional
from .base import BaseTask

logger = logging.getLogger(__name__)


class TaskRegistry:
    """任务注册表 - 单例模式"""
    
    _instance = None
    _tasks: Dict[str, Type[BaseTask]] = {}
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._tasks = {}
        return cls._instance
    
    def register(self, task_class: Type[BaseTask]) -> None:
        """注册任务处理器"""
        if not issubclass(task_class, BaseTask):
            raise TypeError(f"{task_class} must inherit from BaseTask")
        
        task_type = task_class.task_type
        if not task_type:
            raise ValueError(f"{task_class} must define task_type")
        
        self._tasks[task_type] = task_class
        logger.info(f"注册任务: {task_type} -> {task_class.__name__}")
    
    def get(self, task_type: str) -> Optional[Type[BaseTask]]:
        """获取任务处理器类"""
        return self._tasks.get(task_type)
    
    def get_instance(self, task_type: str) -> Optional[BaseTask]:
        """获取任务处理器实例"""
        task_class = self.get(task_type)
        if task_class:
            return task_class()
        return None
    
    def list_tasks(self) -> list:
        """列出所有已注册的任务类型"""
        return list(self._tasks.keys())
    
    def load_tasks_from_dir(self, tasks_dir: str) -> None:
        """从目录动态加载所有任务模块"""
        if not os.path.exists(tasks_dir):
            logger.warning(f"任务目录不存在: {tasks_dir}")
            return
        
        for filename in os.listdir(tasks_dir):
            if filename.startswith('_') or not filename.endswith('.py'):
                continue
            
            module_name = filename[:-3]
            try:
                # 动态导入模块
                module = importlib.import_module(f"tasks.{module_name}")
                
                # 查找继承自 BaseTask 的类
                for attr_name in dir(module):
                    attr = getattr(module, attr_name)
                    if isinstance(attr, type) and issubclass(attr, BaseTask) and attr != BaseTask:
                        self.register(attr)
                        
            except Exception as e:
                logger.error(f"加载任务模块失败 {module_name}: {e}")
    
    def clear(self) -> None:
        """清空注册表（主要用于测试）"""
        self._tasks.clear()


# 全局注册表实例
_registry = TaskRegistry()


def register_task(task_class: Type[BaseTask]) -> None:
    """注册任务处理器（装饰器用法）"""
    _registry.register(task_class)


def get_task(task_type: str) -> Optional[BaseTask]:
    """获取任务处理器实例"""
    return _registry.get_instance(task_type)


def load_all_tasks(tasks_dir: str = None) -> None:
    """加载所有任务"""
    if tasks_dir is None:
        tasks_dir = os.path.join(os.path.dirname(__file__))
    _registry.load_tasks_from_dir(tasks_dir)


def list_tasks() -> list:
    """列出所有已注册的任务"""
    return _registry.list_tasks()
