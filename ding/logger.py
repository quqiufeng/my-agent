#!/usr/bin/env python3
"""
AutoBot Logger - 统一日志模块

特性：
- 彩色控制台输出
- 结构化日志格式
- 多文件日志分流
- 自动日志轮转
- 上下文支持 (task_id, user_id 等)
"""

import os
import sys
import logging
from logging.handlers import RotatingFileHandler

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# 日志目录
LOG_DIR = os.path.join(SCRIPT_DIR, "logs")

# 日志级别配置
LOG_LEVEL = logging.DEBUG  # 开发时用 DEBUG，生产用 INFO

# 颜色代码
COLORS = {
    'RESET': '\033[0m',
    'RED': '\033[91m',
    'GREEN': '\033[92m',
    'YELLOW': '\033[93m',
    'BLUE': '\033[94m',
    'MAGENTA': '\033[95m',
    'CYAN': '\033[96m',
    'WHITE': '\033[97m',
    'GRAY': '\033[90m',
}

# 日志格式模板
LOG_FORMAT_CONSOLE = (
    "%(color)s%(asctime)s%(reset)s "
    "%(color_level)s%(levelname)-8s%(reset)s "
    "%(color_module)s%(name)s%(reset)s "
    "%(message)s"
)

LOG_FORMAT_FILE = (
    "%(asctime)s | %(levelname)-8s | %(name)-20s | "
    "%(task_id)s | %(user_id)s | %(message)s"
)

DATE_FORMAT = "%Y-%m-%d %H:%M:%S"


class ColoredFormatter(logging.Formatter):
    """彩色日志格式化器"""
    
    LEVEL_COLORS = {
        'DEBUG': COLORS['GRAY'],
        'INFO': COLORS['GREEN'],
        'WARNING': COLORS['YELLOW'],
        'ERROR': COLORS['RED'],
        'CRITICAL': COLORS['MAGENTA'],
    }
    
    def __init__(self, fmt=None, datefmt=None):
        super().__init__(fmt, datefmt)
    
    def format(self, record):
        # 保存原始值
        record.color = COLORS['WHITE']
        record.color_level = self.LEVEL_COLORS.get(record.levelname, COLORS['WHITE'])
        record.color_module = COLORS['CYAN']
        record.reset = COLORS['RESET']
        
        # 添加上下文
        record.task_id = getattr(record, 'task_id', '-')
        record.user_id = getattr(record, 'user_id', '-')
        
        return super().format(record)


class ContextFilter(logging.Filter):
    """上下文过滤器"""
    
    # 线程局部存储
    _context = {
        'task_id': None,
        'user_id': None,
        'session_id': None,
    }
    
    def filter(self, record):
        record.task_id = self._context.get('task_id', '-')
        record.user_id = self._context.get('user_id', '-')
        return True


# 全局过滤器
_context_filter = ContextFilter()


def init_logger(name: str, log_file: str = None) -> logging.Logger:
    """
    初始化日志器
    
    Args:
        name: 日志器名称 (通常用 __name__)
        log_file: 指定日志文件 (可选，默认用 name.log)
    
    Returns:
        配置好的 Logger 实例
    """
    # 确保日志目录存在
    os.makedirs(LOG_DIR, exist_ok=True)
    
    logger = logging.getLogger(name)
    logger.setLevel(LOG_LEVEL)
    logger.propagate = False
    
    # 避免重复添加 handler
    if logger.handlers:
        return logger
    
    # 添加上下文过滤器
    logger.addFilter(_context_filter)
    
    # 1. 控制台 Handler (彩色输出)
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.DEBUG)
    console_formatter = ColoredFormatter(LOG_FORMAT_CONSOLE, DATE_FORMAT)
    console_handler.setFormatter(console_formatter)
    logger.addHandler(console_handler)
    
    # 2. 文件 Handler (按模块分流 + 轮转)
    if log_file is None:
        # 转换模块名为文件名: ai.AI -> ai_ai.log
        safe_name = name.replace('.', '_')
        log_file = f"{safe_name}.log"
    
    file_path = os.path.join(LOG_DIR, log_file)
    file_handler = RotatingFileHandler(
        file_path,
        maxBytes=10 * 1024 * 1024,  # 10MB
        backupCount=5,
        encoding='utf-8'
    )
    file_handler.setLevel(logging.DEBUG)
    file_formatter = logging.Formatter(LOG_FORMAT_FILE, DATE_FORMAT)
    file_handler.setFormatter(file_formatter)
    logger.addHandler(file_handler)
    
    return logger


def set_context(task_id: str = None, user_id: str = None, session_id: str = None):
    """设置日志上下文"""
    if task_id is not None:
        ContextFilter._context['task_id'] = task_id
    if user_id is not None:
        ContextFilter._context['user_id'] = user_id
    if session_id is not None:
        ContextFilter._context['session_id'] = session_id


def clear_context():
    """清除日志上下文"""
    ContextFilter._context['task_id'] = None
    ContextFilter._context['user_id'] = None
    ContextFilter._context['session_id'] = None


def get_logger(name: str) -> logging.Logger:
    """获取或创建日志器"""
    return init_logger(name)


# ============================================================
# 便捷函数 - 快速记录日志
# ============================================================

def debug(msg: str, **kwargs):
    """DEBUG 级别日志"""
    logger = get_logger(kwargs.get('module', 'autobot'))
    logger.debug(msg)


def info(msg: str, **kwargs):
    """INFO 级别日志"""
    logger = get_logger(kwargs.get('module', 'autobot'))
    logger.info(msg)


def warning(msg: str, **kwargs):
    """WARNING 级别日志"""
    logger = get_logger(kwargs.get('module', 'autobot'))
    logger.warning(msg)


def error(msg: str, exc_info: bool = False, **kwargs):
    """ERROR 级别日志"""
    logger = get_logger(kwargs.get('module', 'autobot'))
    if exc_info:
        logger.error(msg, exc_info=True)
    else:
        logger.error(msg)


def critical(msg: str, **kwargs):
    """CRITICAL 级别日志"""
    logger = get_logger(kwargs.get('module', 'autobot'))
    logger.critical(msg)


def log_exception(msg: str, **kwargs):
    """记录异常完整的堆栈信息"""
    logger = get_logger(kwargs.get('module', 'autobot'))
    logger.exception(msg)


# ============================================================
# 专用日志器 - 针对特定模块
# ============================================================

# AI 模块日志
ai_logger = init_logger('autobot.ai', 'ai.log')

# 执行器日志
executor_logger = init_logger('autobot.executor', 'executor.log')

# 任务处理日志
task_logger = init_logger('autobot.task', 'task.log')

# 守护进程日志
guardian_logger = init_logger('autobot.guardian', 'guardian.log')

# 钉钉消息日志
dingtalk_logger = init_logger('autobot.dingtalk', 'dingtalk.log')

# 通用日志
app_logger = init_logger('autobot', 'app.log')


if __name__ == "__main__":
    # 测试代码
    logger = init_logger('test')
    
    logger.debug("这是一条调试信息")
    logger.info("这是一条普通信息")
    logger.warning("这是一条警告信息")
    logger.error("这是一条错误信息")
    
    # 测试上下文
    set_context(task_id="task_001", user_id="user_123")
    logger.info("带上下文的日志")
    clear_context()
    
    print(f"\n日志已写入: {LOG_DIR}/")
    print("测试完成!")
