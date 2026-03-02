#!/usr/bin/env python3
"""
Logger 模块 - 统一的日志管理
- 文件日志：丰富格式化，便于调试分析
- 控制台日志：美观易读，带颜色
"""

import os
import sys
import logging
import traceback
from pathlib import Path
from datetime import datetime
from typing import Optional
from logging.handlers import RotatingFileHandler
from dataclasses import dataclass


@dataclass
class LogConfig:
    """日志配置"""

    log_dir: str = ".logs"  # 日志目录
    log_file: str = "app.log"  # 日志文件名
    max_bytes: int = 10 * 1024 * 1024  # 单个日志文件最大 10MB
    backup_count: int = 5  # 保留的备份文件数
    console_level: int = logging.INFO  # 控制台日志级别
    file_level: int = logging.DEBUG  # 文件日志级别
    show_traceback: bool = True  # 是否显示完整堆栈


class Logger:
    """统一日志管理器"""

    # 颜色定义（控制台输出）
    COLORS = {
        "RESET": "\033[0m",
        "DEBUG": "\033[36m",  # 青色
        "INFO": "\033[32m",  # 绿色
        "WARNING": "\033[33m",  # 黄色
        "ERROR": "\033[31m",  # 红色
        "CRITICAL": "\033[35m",  # 紫色
    }

    # 控制台格式（美观易读）
    CONSOLE_FORMAT = "{color}[{level}]{reset} {message}"
    CONSOLE_MSG_FORMAT = "{time} {color}{level}{reset} {msg}"

    # 文件格式（丰富详细，便于调试）
    FILE_FORMAT = (
        "%(asctime)s.%(msecs)03d | "
        "%(levelname)-8s | "
        "%(threadName)-10s | "
        "%(name)s.%(funcName)s:%(lineno)d | "
        "%(message)s"
    )

    def __init__(
        self,
        name: str = "app",
        log_dir: str = ".logs",
        log_file: str = "app.log",
        level: int = logging.DEBUG,
        show_traceback: bool = True,
    ):
        """
        初始化日志器

        Args:
            name: 日志器名称
            log_dir: 日志目录
            log_file: 日志文件名
            level: 日志级别
            show_traceback: 是否在异常时显示完整堆栈
        """
        self.name = name
        self.log_dir = Path(log_dir)
        self.log_file = log_file
        self.show_traceback = show_traceback

        # 分离文件logger和控制台logger，避免颜色序列写入文件
        self._file_logger = logging.getLogger(f"{name}.file")
        self._file_logger.setLevel(level)
        self._file_logger.handlers.clear()

        self._console_logger = logging.getLogger(name)
        self._console_logger.setLevel(level)
        self._console_logger.handlers.clear()

        # 创建日志目录
        self.log_dir.mkdir(parents=True, exist_ok=True)

        # 添加文件处理器
        self._add_file_handler(level)

        # 添加控制台处理器
        self._add_console_handler()

    def _add_file_handler(self, level: int):
        """添加文件处理器"""
        log_path = self.log_dir / self.log_file

        handler = RotatingFileHandler(
            log_path,
            maxBytes=10 * 1024 * 1024,  # 10MB
            backupCount=5,
            encoding="utf-8",
        )

        handler.setLevel(level)

        # 详细文件格式
        formatter = logging.Formatter(self.FILE_FORMAT, datefmt="%Y-%m-%d %H:%M:%S")
        handler.setFormatter(formatter)

        self._file_logger.addHandler(handler)

    def _add_console_handler(self):
        """添加控制台处理器（带颜色）"""
        handler = logging.StreamHandler(sys.stdout)
        handler.setLevel(logging.DEBUG)

        # 控制台使用简单格式，依赖颜色
        formatter = logging.Formatter("%(message)s")
        handler.setFormatter(formatter)

        self._file_logger.addHandler(handler)

    def _format_console(self, level: int, message: str) -> str:
        """格式化控制台输出（带颜色）"""
        level_name = logging.getLevelName(level)
        color = self.COLORS.get(level_name, self.COLORS["RESET"])
        reset = self.COLORS["RESET"]

        # 获取当前时间
        now = datetime.now().strftime("%H:%M:%S")

        # 不同级别不同格式
        if level >= logging.ERROR:
            # 错误：显示简洁但醒目
            return f"{now} {color}✗ {message}{reset}"
        elif level >= logging.WARNING:
            # 警告：显示简洁但醒目
            return f"{now} {color}⚠ {message}{reset}"
        elif level >= logging.INFO:
            # 信息：简洁
            return f"{now} {color}●{reset} {message}"
        else:
            # 调试：详细
            return f"{now} {color}○{reset} {message}"

    def debug(self, msg: str, **kwargs):
        """调试日志"""
        console_msg = self._format_console(logging.DEBUG, msg)
        self._console_logger.debug(console_msg, **kwargs)
        self._file_logger.debug(msg, **kwargs)

    def info(self, msg: str, **kwargs):
        """信息日志"""
        console_msg = self._format_console(logging.INFO, msg)
        self._console_logger.info(console_msg, **kwargs)
        self._file_logger.info(msg, **kwargs)

    def warning(self, msg: str, **kwargs):
        """警告日志"""
        console_msg = self._format_console(logging.WARNING, msg)
        self._console_logger.warning(console_msg, **kwargs)
        self._file_logger.warning(msg, **kwargs)

    def error(
        self,
        msg: str,
        exc_info: Optional[bool] = None,
        context: Optional[dict] = None,
        **kwargs,
    ):
        """错误日志"""
        if exc_info is None:
            exc_info = self.show_traceback

        if context:
            msg = f"{msg}\n  Context: {context}"

        console_msg = self._format_console(logging.ERROR, msg)
        self._console_logger.error(console_msg, exc_info=exc_info, **kwargs)
        self._file_logger.error(msg, exc_info=exc_info, **kwargs)

    def critical(self, msg: str, exc_info: bool = True, **kwargs):
        """严重错误日志"""
        console_msg = self._format_console(logging.CRITICAL, msg)
        self._console_logger.critical(console_msg, exc_info=exc_info, **kwargs)
        self._file_logger.critical(msg, exc_info=exc_info, **kwargs)

    def exception(self, msg: str, **kwargs):
        """异常日志（自动包含堆栈）"""
        self.error(msg, exc_info=True, **kwargs)

    def log(self, level: int, msg: str, **kwargs):
        """通用日志方法"""
        console_msg = self._format_console(level, msg)
        self._console_logger.log(level, console_msg, **kwargs)
        self._file_logger.log(level, msg, **kwargs)

    def log_dict(self, data: dict, prefix: str = "", level: int = logging.DEBUG):
        """记录字典数据（用于调试）"""
        if prefix:
            msg = prefix + "\n"
        else:
            msg = ""

        for key, value in data.items():
            msg += f"  {key}: {value}\n"

        self.log(level, msg.rstrip())

    def log_request(self, method: str, url: str, **kwargs):
        """记录 HTTP 请求"""
        self.info(f"→ {method} {url}")
        if kwargs.get("headers"):
            self.debug(f"  Headers: {kwargs['headers']}")
        if kwargs.get("json"):
            self.debug(f"  Body: {kwargs['json']}")

    def log_response(
        self, status: int, url: str, elapsed: Optional[float] = None, **kwargs
    ):
        """记录 HTTP 响应"""
        if elapsed is not None:
            self.info(f"← {status} {url} ({elapsed:.2f}s)")
        else:
            self.info(f"← {status} {url}")

        if kwargs.get("data"):
            self.debug(f"  Response: {kwargs['data'][:200]}...")

    def log_error_with_context(
        self, msg: str, context: Optional[dict] = None, exc_info: bool = True
    ):
        """
        记录带上下文的错误

        Args:
            msg: 错误消息
            context: 上下文数据字典
            exc_info: 是否显示异常堆栈
        """
        full_msg = msg
        if context:
            full_msg += f"\n  Context: {context}"

        self.error(full_msg, exc_info=exc_info)


# 全局日志器
_default_logger: Optional[Logger] = None


def get_logger(
    name: str = "app",
    log_dir: str = ".logs",
    log_file: str = "app.log",
    level: int = logging.DEBUG,
) -> Logger:
    """
    获取全局日志器（单例）

    Args:
        name: 日志器名称
        log_dir: 日志目录
        log_file: 日志文件名
        level: 日志级别

    Returns:
        Logger 实例
    """
    global _default_logger
    if _default_logger is None:
        _default_logger = Logger(
            name=name,
            log_dir=log_dir,
            log_file=log_file,
            level=level,
        )
    return _default_logger


# 便捷函数
def debug(msg: str, **kwargs):
    get_logger().debug(msg, **kwargs)


def info(msg: str, **kwargs):
    get_logger().info(msg, **kwargs)


def warning(msg: str, **kwargs):
    get_logger().warning(msg, **kwargs)


def error(msg: str, exc_info: Optional[bool] = None, **kwargs):
    get_logger().error(msg, exc_info=exc_info, **kwargs)


def critical(msg: str, **kwargs):
    get_logger().critical(msg, **kwargs)


def exception(msg: str, **kwargs):
    get_logger().exception(msg, **kwargs)


if __name__ == "__main__":
    # 测试
    print("=== Logger 测试 ===\n")

    logger = Logger("test", log_dir=".logs", log_file="test.log")

    logger.debug("这是一条调试信息")
    logger.info("这是一条普通信息")
    logger.warning("这是一条警告信息")

    try:
        1 / 0
    except Exception:
        logger.exception("发生了一个错误")

    logger.log_dict({"name": "张三", "age": 25, "city": "北京"}, "用户信息:")

    logger.info("→ GET https://api.example.com/users")
    logger.info("← 200 https://api.example.com/users (0.5s)")

    logger.error("业务错误", context={"user_id": 12345, "action": "login"})
