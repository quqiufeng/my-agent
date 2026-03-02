#!/usr/bin/env python3
"""
Scanner模块 - 扫描项目代码并生成摘要
为远程大模型提供项目上下文
"""

import os
from pathlib import Path
from typing import List, Dict, Optional


class Scanner:
    """项目代码扫描器"""

    # 忽略的目录和文件
    IGNORE_DIRS = {
        '.git', '__pycache__', '.pytest_cache', '.venv', 'venv',
        'node_modules', '.idea', '.vscode', 'dist', 'build', '.eggs',
        '*.pyc', '.tox', '.coverage', '.mypy_cache'
    }

    # 只扫描这些类型的文件
    CODE_EXTENSIONS = {'.py', '.js', '.ts', '.jsx', '.tsx', '.json', '.yaml',
                      '.yml', '.toml', '.ini', '.cfg', '.md', '.txt'}

    def __init__(self, project_root: str = "."):
        self.project_root = Path(project_root)

    def scan_files(self, max_files: int = 20) -> List[Path]:
        """
        扫描项目中的代码文件

        Args:
            max_files: 最大扫描文件数

        Returns:
            文件路径列表
        """
        files = []

        for ext in self.CODE_EXTENSIONS:
            pattern = f"**/*{ext}"
            for f in self.project_root.rglob(pattern):
                # 跳过忽略的目录
                if any(ignore in f.parts for ignore in self.IGNORE_DIRS):
                    continue
                if f.is_file() and f.stat().st_size < 1024 * 1024:  # 小于1MB
                    files.append(f)

        # 按修改时间排序，取最新的
        files.sort(key=lambda x: x.stat().st_mtime, reverse=True)
        return files[:max_files]

    def read_file_content(self, file_path: Path, max_lines: int = 100) -> str:
        """
        读取文件内容（限制行数）

        Args:
            file_path: 文件路径
            max_lines: 最大行数

        Returns:
            文件内容字符串
        """
        try:
            content = file_path.read_text(encoding='utf-8', errors='ignore')
            lines = content.split('\n')

            # 如果文件太长，截断并添加说明
            if len(lines) > max_lines:
                truncated = '\n'.join(lines[:max_lines])
                return f"{truncated}\n\n... (共 {len(lines)} 行，已截断)"

            return content
        except Exception as e:
            return f"[无法读取文件: {e}]"

    def get_file_summary(self, file_path: Path) -> Dict:
        """
        获取文件的摘要信息

        Args:
            file_path: 文件路径

        Returns:
            包含摘要信息的字典
        """
        try:
            content = file_path.read_text(encoding='utf-8', errors='ignore')
            lines = content.split('\n')

            # 统计信息
            stats = {
                'path': str(file_path.relative_to(self.project_root)),
                'lines': len(lines),
                'size': file_path.stat().st_size,
                'functions': [],
                'classes': [],
                'imports': [],
            }

            # 提取函数和类
            for line in lines:
                stripped = line.strip()
                if stripped.startswith('def '):
                    stats['functions'].append(stripped[4:].split('(')[0])
                elif stripped.startswith('class '):
                    stats['classes'].append(stripped[6:].split('(')[0])
                elif stripped.startswith('import ') or stripped.startswith('from '):
                    stats['imports'].append(stripped)

            return stats
        except Exception as e:
            return {'path': str(file_path), 'error': str(e)}

    def generate_summary(self) -> str:
        """
        生成项目代码摘要

        Returns:
            格式化的摘要字符串
        """
        files = self.scan_files()

        if not files:
            return "=== 项目摘要 ===\n项目中没有找到代码文件"

        sections = ["=== 项目代码摘要 ==="]

        for file_path in files[:10]:  # 限制数量
            rel_path = file_path.relative_to(self.project_root)
            summary = self.get_file_summary(file_path)

            sections.append(f"\n--- {rel_path} ({summary.get('lines', 0)} 行) ---")

            if summary.get('classes'):
                sections.append(f"类: {', '.join(summary['classes'][:3])}")

            if summary.get('functions'):
                sections.append(f"函数: {', '.join(summary['functions'][:5])}")

            if summary.get('imports'):
                sections.append(f"导入: {', '.join(summary['imports'][:3])}")

        return "\n".join(sections)

    def get_file_tree(self, max_depth: int = 3) -> str:
        """
        获取项目的文件树

        Args:
            max_depth: 最大深度

        Returns:
            文件树字符串
        """
        lines = ["=== 项目文件树 ==="]

        def format_tree(path: Path, prefix: str = "", depth: int = 0):
            if depth > max_depth:
                return

            try:
                items = sorted(path.iterdir(), key=lambda x: (not x.is_dir(), x.name))
            except PermissionError:
                return

            skip = {'.git', '__pycache__', 'venv', 'node_modules', '.venv'}

            for i, item in enumerate(items):
                if item.name.startswith('.') or item.name in skip:
                    continue

                is_last = i == len(items) - 1
                connector = "└── " if is_last else "├── "

                if item.is_dir():
                    lines.append(f"{prefix}{connector}{item.name}/")
                    new_prefix = prefix + ("    " if is_last else "│   ")
                    format_tree(item, new_prefix, depth + 1)
                else:
                    lines.append(f"{prefix}{connector}{item.name}")

        format_tree(self.project_root)
        return "\n".join(lines[:60])


def scan_project(project_root: str = ".") -> str:
    """
    便捷函数：扫描项目并生成摘要

    Args:
        project_root: 项目根目录

    Returns:
        项目摘要字符串
    """
    scanner = Scanner(project_root)
    return scanner.generate_summary()


if __name__ == '__main__':
    # 测试
    print("=== 项目扫描测试 ===")
    result = scan_project(".")
    print(result)
