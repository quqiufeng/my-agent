#!/usr/bin/env python3
"""
Scanner 模块 - 项目扫描器
扫描项目结构，生成上下文快照，供大模型了解项目现状
"""

import os
import sys
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Dict, Optional
from datetime import datetime
import subprocess

# 确保导入路径正确
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from logger import get_logger

logger = get_logger("scanner")


@dataclass
class FileInfo:
    """文件信息"""

    path: str
    size: int
    modified: str
    is_dir: bool = False


@dataclass
class ProjectContext:
    """项目上下文快照"""

    root: str
    name: str
    structure: str = ""
    files: List[FileInfo] = field(default_factory=list)
    dependencies: Dict[str, str] = field(default_factory=dict)
    git_branch: str = ""
    git_status: str = ""
    recent_commits: List[str] = field(default_factory=list)
    python_version: str = ""
    venv_active: bool = False
    readme_summary: str = ""
    custom_context: Dict[str, str] = field(default_factory=dict)

    def to_prompt_text(self) -> str:
        """转换为提示词文本"""
        lines = []

        # 项目基本信息
        lines.append(f"## 项目: {self.name}")
        lines.append(f"**根目录**: {self.root}")
        lines.append(f"**Python版本**: {self.python_version}")
        if self.venv_active:
            lines.append("**虚拟环境**: 已激活")
        lines.append("")

        # Git 状态
        if self.git_branch or self.git_status:
            lines.append("### Git 状态")
            if self.git_branch:
                lines.append(f"当前分支: {self.git_branch}")
            if self.git_status:
                lines.append(f"状态: {self.git_status}")
            lines.append("")

        # 最近提交
        if self.recent_commits:
            lines.append("### 最近提交")
            for commit in self.recent_commits[:5]:
                lines.append(f"- {commit}")
            lines.append("")

        # 项目结构
        if self.structure:
            lines.append("### 项目结构")
            lines.append(self.structure)
            lines.append("")

        # 依赖
        if self.dependencies:
            lines.append("### 依赖")
            for name, version in self.dependencies.items():
                lines.append(f"- {name}: {version}")
            lines.append("")

        # README 摘要
        if self.readme_summary:
            lines.append("### README 摘要")
            lines.append(self.readme_summary[:500])
            lines.append("")

        return "\n".join(lines)


class Scanner:
    """项目扫描器"""

    # 忽略的目录
    IGNORE_DIRS = {
        "__pycache__",
        ".git",
        ".ruff_cache",
        ".venv",
        "venv",
        "env",
        ".env",
        "node_modules",
        ".idea",
        ".vscode",
        "dist",
        "build",
        ".pytest_cache",
        ".mypy_cache",
    }

    # 忽略的文件
    IGNORE_FILES = {
        ".DS_Store",
        "Thumbs.db",
        "*.pyc",
        "*.pyo",
        "*.log",
    }

    # 需要读取内容的文件类型
    READABLE_EXTENSIONS = {".py", ".md", ".txt", ".json", ".yaml", ".yml", ".toml"}

    def __init__(self, project_root: str = "."):
        self.root = Path(project_root).absolute()
        self.logger = logger

    def scan(self) -> ProjectContext:
        """
        执行完整扫描

        Returns:
            ProjectContext: 项目上下文
        """
        self.logger.info(f"开始扫描项目: {self.root}")

        context = ProjectContext(
            root=str(self.root),
            name=self.root.name,
            python_version=self._get_python_version(),
            venv_active=self._is_venv_active(),
        )

        # 扫描项目结构
        context.structure = self._scan_structure()

        # 扫描文件列表
        context.files = self._scan_files()

        # 获取依赖
        context.dependencies = self._scan_dependencies()

        # Git 信息
        context.git_branch = self._get_git_branch()
        context.git_status = self._get_git_status()
        context.recent_commits = self._get_recent_commits()

        # README 摘要
        context.readme_summary = self._get_readme_summary()

        self.logger.info(f"扫描完成，发现 {len(context.files)} 个文件")
        return context

    def _get_python_version(self) -> str:
        """获取 Python 版本"""
        version = sys.version.split()[0]
        return version

    def _is_venv_active(self) -> bool:
        """检查是否激活了虚拟环境"""
        return hasattr(sys, "real_prefix") or (
            hasattr(sys, "base_prefix") and sys.base_prefix != sys.prefix
        )

    def _scan_structure(self, max_depth: int = 3) -> str:
        """扫描目录结构"""
        lines = []
        root_len = len(self.root.parts)

        def walk_dir(path: Path, depth: int = 0):
            if depth > max_depth:
                return

            try:
                entries = sorted(path.iterdir(), key=lambda x: (not x.is_dir(), x.name))
            except PermissionError:
                return

            dirs = []
            for entry in entries:
                if entry.is_dir():
                    if entry.name in self.IGNORE_DIRS:
                        continue
                    dirs.append(entry)

            for i, d in enumerate(dirs):
                is_last = i == len(dirs) - 1
                indent = "  " * depth
                lines.append(f"{indent}📁 {d.name}/")
                walk_dir(d, depth + 1)

        walk_dir(self.root)

        return "\n".join(lines[:50])

    def _scan_files(self, max_files: int = 100) -> List[FileInfo]:
        """扫描文件列表"""
        files = []

        for path in sorted(self.root.rglob("*")):
            if path.is_file():
                # 检查是否忽略
                if path.name in self.IGNORE_FILES:
                    continue
                if any(
                    path.name.endswith(ext.replace("*", ""))
                    for ext in self.IGNORE_FILES
                ):
                    continue

                # 检查父目录是否忽略
                if any(ignored in path.parts for ignored in self.IGNORE_DIRS):
                    continue

                # 获取修改时间
                try:
                    mtime = datetime.fromtimestamp(path.stat().st_mtime)
                    modified = mtime.strftime("%Y-%m-%d %H:%M")
                except:
                    modified = "unknown"

                files.append(
                    FileInfo(
                        path=str(path.relative_to(self.root)),
                        size=path.stat().st_size,
                        modified=modified,
                    )
                )

                if len(files) >= max_files:
                    break

        return files

    def _scan_dependencies(self) -> Dict[str, str]:
        """扫描项目依赖"""
        deps = {}

        # requirements.txt
        req_file = self.root / "requirements.txt"
        if req_file.exists():
            try:
                content = req_file.read_text(encoding="utf-8")
                for line in content.split("\n"):
                    line = line.strip()
                    if line and not line.startswith("#"):
                        # 简单解析 name==version 或 name>=version
                        if "==" in line:
                            name, version = line.split("==", 1)
                            deps[name.strip()] = version.strip()
                        elif ">=" in line:
                            name, version = line.split(">=", 1)
                            deps[name.strip()] = f">={version.strip()}"
                        else:
                            deps[line] = "latest"
            except Exception as e:
                self.logger.warning(f"读取 requirements.txt 失败: {e}")

        # pyproject.toml
        pyproject = self.root / "pyproject.toml"
        if pyproject.exists():
            try:
                content = pyproject.read_text(encoding="utf-8")
                # 简单提取 dependencies 段
                in_deps = False
                for line in content.split("\n"):
                    if (
                        "[project.dependencies]" in line
                        or "[tool.poetry.dependencies]" in line
                    ):
                        in_deps = True
                        continue
                    if in_deps:
                        if line.startswith("["):
                            break
                        if "=" in line:
                            dep = line.strip().strip('"').strip("'")
                            if dep:
                                deps[dep] = "see pyproject.toml"
            except Exception as e:
                self.logger.warning(f"读取 pyproject.toml 失败: {e}")

        return deps

    def _get_git_branch(self) -> str:
        """获取当前分支"""
        try:
            result = subprocess.run(
                ["git", "branch", "--show-current"],
                cwd=self.root,
                capture_output=True,
                text=True,
                timeout=5,
            )
            return result.stdout.strip() or ""
        except:
            return ""

    def _get_git_status(self) -> str:
        """获取 Git 状态"""
        try:
            result = subprocess.run(
                ["git", "status", "--short"],
                cwd=self.root,
                capture_output=True,
                text=True,
                timeout=5,
            )
            status = result.stdout.strip()
            if status:
                lines = status.split("\n")
                # 限制显示数量
                if len(lines) > 10:
                    return (
                        "\n".join(lines[:10]) + f"\n... 还有 {len(lines) - 10} 个文件"
                    )
                return status
            return "clean"
        except:
            return ""

    def _get_recent_commits(self, count: int = 5) -> List[str]:
        """获取最近提交"""
        try:
            result = subprocess.run(
                ["git", "log", f"-{count}", "--oneline"],
                cwd=self.root,
                capture_output=True,
                text=True,
                timeout=5,
            )
            return [
                line.strip()
                for line in result.stdout.strip().split("\n")
                if line.strip()
            ]
        except:
            return []

    def _get_readme_summary(self) -> str:
        """获取 README 摘要"""
        for name in ["README.md", "README.txt", "README"]:
            readme = self.root / name
            if readme.exists():
                try:
                    content = readme.read_text(encoding="utf-8")
                    # 移除 markdown 图片和链接
                    import re

                    content = re.sub(r"!\[.*?\]\(.*?\)", "", content)
                    content = re.sub(r"\[.*?\]\(.*?\)", r"\1", content)
                    content = re.sub(r"#{1,6}\s+", "", content)
                    content = re.sub(r"\n{3,}", "\n\n", content)
                    return content.strip()[:1000]
                except:
                    pass
        return ""

    def read_file_for_context(self, file_path: str, max_lines: int = 100) -> str:
        """
        读取文件内容用于上下文

        Args:
            file_path: 文件路径（相对于项目根目录）
            max_lines: 最大行数

        Returns:
            文件内容
        """
        path = self.root / file_path
        if not path.exists():
            return f"[文件不存在: {file_path}]"

        # 检查扩展名
        if path.suffix not in self.READABLE_EXTENSIONS:
            return f"[二进制文件: {file_path}]"

        try:
            lines = path.read_text(encoding="utf-8").split("\n")
            if len(lines) > max_lines:
                return "\n".join(lines[:max_lines]) + f"\n... 共 {len(lines)} 行"
            return "\n".join(lines)
        except Exception as e:
            return f"[读取失败: {e}]"

    def get_file_tree(self, max_depth: int = 3, include_files: bool = False) -> str:
        """
        获取文件树

        Args:
            max_depth: 最大深度
            include_files: 是否包含文件

        Returns:
            树形结构字符串
        """
        lines = [self.root.name]

        def walk(path: Path, prefix: str = "", depth: int = 0):
            if depth > max_depth:
                return

            try:
                entries = sorted(path.iterdir(), key=lambda x: (not x.is_dir(), x.name))
            except PermissionError:
                return

            dirs = [e for e in entries if e.is_dir() and e.name not in self.IGNORE_DIRS]
            files = [e for e in entries if e.is_file()] if include_files else []

            for i, d in enumerate(dirs):
                is_last = (i == len(dirs) - 1) and (len(files) == 0)
                new_prefix = prefix + ("    " if is_last else "│   ")
                lines.append(f"{prefix}{'└── ' if is_last else '├── '}{d.name}/")
                walk(d, new_prefix, depth + 1)

            for i, f in enumerate(files):
                is_last = i == len(files) - 1
                lines.append(f"{prefix}{'└── ' if is_last else '├── '}{f.name}")

        walk(self.root)
        return "\n".join(lines[:100])


def scan_project(project_root: str = ".") -> ProjectContext:
    """
    便捷函数：扫描项目

    Args:
        project_root: 项目根目录

    Returns:
        ProjectContext: 项目上下文
    """
    scanner = Scanner(project_root)
    return scanner.scan()


if __name__ == "__main__":
    # 测试
    print("=== Scanner 测试 ===\n")

    scanner = Scanner(".")
    context = scanner.scan()

    print("项目信息:")
    print(f"  名称: {context.name}")
    print(f"  根目录: {context.root}")
    print(f"  Python版本: {context.python_version}")
    print(f"  虚拟环境: {'是' if context.venv_active else '否'}")
    print()

    print("Git信息:")
    print(f"  分支: {context.git_branch}")
    print(f"  状态: {context.git_status}")
    print(f"  最近提交: {context.recent_commits}")
    print()

    print("项目结构:")
    print(context.structure)
    print()

    print("依赖:")
    for k, v in context.dependencies.items():
        print(f"  {k}: {v}")
    print()

    print("README摘要:")
    print(context.readme_summary[:300])
    print()

    print("文件树:")
    print(scanner.get_file_tree(max_depth=2, include_files=True))
