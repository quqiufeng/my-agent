#!/usr/bin/env python3
"""
Logger模块 - 操作日志记录
记录所有执行的操作，供远程大模型参考
"""

import os
import json
import logging
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional
from dataclasses import dataclass, asdict


@dataclass
class LogEntry:
    """日志条目"""
    timestamp: str
    type: str          # shell/code/file/dir/log
    action: str        # 具体操作
    target: str        # 目标路径/命令
    success: bool
    result: str        # 执行结果
    error: str = ""    # 错误信息


class Logger:
    """日志记录器"""

    def __init__(self, project_root: str = "."):
        self.project_root = Path(project_root)
        self.log_dir = self.project_root / ".opencode_logs"
        self.log_dir.mkdir(exist_ok=True)

        # 日志文件
        self.log_file = self.log_dir / "execution.log"
        self.json_log_file = self.log_dir / "execution.json"

        # Python logging
        self._setup_python_logger()

        # 内存日志
        self.entries: List[LogEntry] = []

    def _setup_python_logger(self):
        """配置Python标准日志"""
        self.logger = logging.getLogger("opencode")
        self.logger.setLevel(logging.DEBUG)

        # 文件处理器
        fh = logging.FileHandler(self.log_file, encoding='utf-8')
        fh.setLevel(logging.DEBUG)

        # 控制台处理器
        ch = logging.StreamHandler()
        ch.setLevel(logging.INFO)

        # 格式
        formatter = logging.Formatter(
            '%(asctime)s - %(levelname)s - %(message)s'
        )
        fh.setFormatter(formatter)
        ch.setFormatter(formatter)

        self.logger.addHandler(fh)
        self.logger.addHandler(ch)

    def log(
        self,
        action_type: str,
        action: str,
        target: str,
        success: bool,
        result: str,
        error: str = ""
    ):
        """
        记录操作日志

        Args:
            action_type: 操作类型 (shell/code/file/dir/log)
            action: 动作描述
            target: 目标
            success: 是否成功
            result: 结果
            error: 错误信息
        """
        entry = LogEntry(
            timestamp=datetime.now().isoformat(),
            type=action_type,
            action=action,
            target=target,
            success=success,
            result=result,
            error=error
        )

        self.entries.append(entry)

        # 写入Python日志
        level = logging.INFO if success else logging.ERROR
        msg = f"[{action_type}] {action} -> {target}: {result}"
        if error:
            msg += f" | Error: {error}"
        self.logger.log(level, msg)

        # 保存到JSON
        self._save_json()

    def log_shell(self, command: str, success: bool, output: str, error: str = ""):
        """记录Shell命令"""
        self.log("shell", "执行命令", command, success, output, error)

    def log_code(self, code: str, success: bool, output: str, error: str = ""):
        """记录Python代码执行"""
        self.log("code", "执行代码", code[:50], success, output, error)

    def log_file(self, file_path: str, success: bool, result: str, error: str = ""):
        """记录文件操作"""
        self.log("file", "写入文件", file_path, success, result, error)

    def log_dir_created(self, dir_path: str, success: bool, result: str, error: str = ""):
        """记录目录创建"""
        self.log("dir", "创建目录", dir_path, success, result, error)

    def log_log(self, file_path: str, success: bool, result: str, error: str = ""):
        """记录日志添加"""
        self.log("log", "添加日志", file_path, success, result, error)

    def _save_json(self):
        """保存JSON格式日志"""
        data = [asdict(e) for e in self.entries]
        self.json_log_file.write_text(
            json.dumps(data, indent=2, ensure_ascii=False),
            encoding='utf-8'
        )

    def get_recent_logs(self, count: int = 10) -> List[LogEntry]:
        """
        获取最近的日志

        Args:
            count: 获取数量

        Returns:
            日志列表
        """
        return self.entries[-count:]

    def get_logs_by_type(self, log_type: str) -> List[LogEntry]:
        """
        按类型获取日志

        Args:
            log_type: 日志类型

        Returns:
            匹配的日志列表
        """
        return [e for e in self.entries if e.type == log_type]

    def get_failed_logs(self) -> List[LogEntry]:
        """
        获取失败的日志

        Returns:
            失败的日志列表
        """
        return [e for e in self.entries if not e.success]

    def generate_summary(self) -> str:
        """
        生成日志摘要

        Returns:
            格式化的摘要
        """
        if not self.entries:
            return "=== 日志摘要 ===\n暂无日志"

        lines = ["=== 执行日志摘要 ==="]

        # 统计
        total = len(self.entries)
        success = len([e for e in self.entries if e.success])
        failed = total - success

        lines.append(f"\n总操作: {total}")
        lines.append(f"成功: {success}")
        lines.append(f"失败: {failed}")

        # 按类型统计
        types = {}
        for e in self.entries:
            types[e.type] = types.get(e.type, 0) + 1

        lines.append("\n按类型统计:")
        for t, c in types.items():
            lines.append(f"  {t}: {c}")

        # 最近操作
        lines.append("\n最近操作:")
        for entry in self.entries[-5:]:
            status = "✓" if entry.success else "✗"
            lines.append(f"  {status} #{entry.type} {entry.target}")

        return "\n".join(lines)

    def clear(self):
        """清空日志"""
        self.entries = []
        if self.json_log_file.exists():
            self.json_log_file.unlink()
        if self.log_file.exists():
            self.log_file.unlink()


# ==================== 日志辅助函数 ====================

def add_log_statements(file_path: str, logger_name: str = None) -> str:
    """
    为文件生成日志语句模板

    Args:
        file_path: 文件路径
        logger_name: logger名称

    Returns:
        日志语句模板
    """
    logger = logger_name or Path(file_path).stem

    template = f'''
import logging

# 配置日志
logger = logging.getLogger("{logger}")
logger.setLevel(logging.DEBUG)

handler = logging.StreamHandler()
handler.setLevel(logging.DEBUG)
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
handler.setFormatter(formatter)
logger.addHandler(handler)

# 使用示例:
# logger.debug("调试信息")
# logger.info("一般信息")
# logger.warning("警告信息")
# logger.error("错误信息")
# logger.critical("严重错误")
'''
    return template.strip()


# ==================== 全局日志器 ====================

# 创建全局日志器实例
_default_logger: Optional[Logger] = None


def get_logger(project_root: str = ".") -> Logger:
    """获取全局日志器"""
    global _default_logger
    if _default_logger is None:
        _default_logger = Logger(project_root)
    return _default_logger


if __name__ == '__main__':
    # 测试
    print("=== Logger 测试 ===")

    logger = Logger(".")

    # 模拟记录
    logger.log_shell("pip install requests", True, "安装成功")
    logger.log_file("test.py", True, "文件已创建")
    logger.log_shell("ls", False, "", "命令不存在")

    print(logger.generate_summary())
