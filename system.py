#!/usr/bin/env python3
"""
System模块 - 收集系统环境信息和项目能力
让远程大模型了解当前环境状况
"""

import os
import sys
import platform
import subprocess
from pathlib import Path
from typing import Dict, List, Optional


class SystemInfo:
    """系统信息收集器"""

    def __init__(self, project_root: str = "."):
        self.project_root = Path(project_root)

    def get_os_info(self) -> str:
        """获取操作系统信息"""
        info = [
            f"OS: {platform.system()}-{platform.release()}",
            f"Architecture: {platform.machine()}",
            f"Python: {sys.version.split()[0]}",
            f"Working Directory: {os.getcwd()}",
        ]
        return "\n".join(info)

    def get_installed_packages(self, limit: int = 20) -> str:
        """获取已安装的关键Python包"""
        try:
            result = subprocess.run(
                [sys.executable, "-m", "pip", "list", "--format=freeze"],
                capture_output=True,
                text=True,
                timeout=10
            )
            packages = result.stdout.strip().split("\n")
            # 过滤掉系统包
            important = [p for p in packages[:limit] if not p.startswith("(")]
            return "=== 已安装核心包 ===\n" + "\n".join(important)
        except Exception as e:
            return f"无法获取包列表: {e}"

    def get_project_structure(self, max_depth: int = 3) -> str:
        """获取项目目录结构"""
        lines = ["=== 项目结构 ==="]

        def walk_dir(path: Path, prefix: str = "", depth: int = 0):
            if depth > max_depth:
                return

            try:
                items = sorted(path.iterdir(), key=lambda x: (x.is_file(), x.name))
            except PermissionError:
                return

            # 跳过隐藏目录和常见忽略目录
            skip_dirs = {'.git', '__pycache__', '.pytest_cache', 'venv', '.venv',
                        'node_modules', '.idea', '.vscode', 'dist', 'build'}

            for i, item in enumerate(items):
                if item.name.startswith('.') or item.name in skip_dirs:
                    continue

                is_last = i == len(items) - 1
                connector = "└── " if is_last else "├── "

                if item.is_dir():
                    lines.append(f"{prefix}{connector}{item.name}/")
                    new_prefix = prefix + ("    " if is_last else "│   ")
                    walk_dir(item, new_prefix, depth + 1)
                else:
                    # 只显示代码文件
                    if item.suffix in {'.py', '.js', '.ts', '.json', '.yaml', '.yml',
                                      '.txt', '.md', '.toml', '.ini', '.cfg'}:
                        lines.append(f"{prefix}{connector}{item.name}")

        if self.project_root.exists():
            project_name = self.project_root.name
            lines[0] = f"=== 项目结构: {project_name} ==="
            walk_dir(self.project_root)

        return "\n".join(lines[:100])  # 限制行数

    def get_existing_capabilities(self) -> str:
        """获取现有代码的能力摘要"""
        lines = ["=== 现有模块能力 ==="]

        py_files = list(self.project_root.rglob("*.py"))
        py_files = [f for f in py_files if '__pycache__' not in str(f)]

        for py_file in py_files[:10]:  # 限制数量
            try:
                rel_path = py_file.relative_to(self.project_root)
                content = py_file.read_text(encoding='utf-8', errors='ignore')
                lines.append(f"\n--- {rel_path} ---")

                # 提取函数和类定义
                functions = []
                classes = []

                for line in content.split('\n'):
                    stripped = line.strip()
                    if stripped.startswith('def '):
                        func_name = stripped[4:].split('(')[0]
                        functions.append(func_name)
                    elif stripped.startswith('class '):
                        class_name = stripped[6:].split('(')[0]
                        classes.append(class_name)

                if classes:
                    lines.append(f"类: {', '.join(classes[:5])}")
                if functions:
                    lines.append(f"函数: {', '.join(functions[:5])}")

            except Exception:
                continue

        return "\n".join(lines[:50])  # 限制行数

    def collect_all(self) -> str:
        """收集所有系统信息"""
        sections = [
            "=== 系统环境 ===",
            self.get_os_info(),
            "",
            self.get_installed_packages(),
            "",
            self.get_project_structure(),
            "",
            self.get_existing_capabilities(),
        ]
        return "\n".join(sections)


def get_system_info(project_root: str = ".") -> str:
    """
    便捷函数：获取完整的系统信息

    Args:
        project_root: 项目根目录路径

    Returns:
        格式化的系统信息字符串
    """
    info_collector = SystemInfo(project_root)
    return info_collector.collect_all()


if __name__ == '__main__':
    # 测试
    print("=== 系统信息收集测试 ===")
    info = get_system_info(".")
    print(info)
