#!/usr/bin/env python3
"""
Debugger模块 - 调试和自省模式
支持语法检查、导入测试、单元测试，以及对陌生库的API自省
"""

import os
import sys
import ast
import inspect
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple


class Debugger:
    """调试器和自省工具"""

    def __init__(self, project_root: str = "."):
        self.project_root = Path(project_root).absolute()

    def check_syntax(self, code: str, filename: str = "<string>") -> Tuple[bool, str]:
        """
        检查Python代码语法

        Args:
            code: Python代码
            filename: 文件名（用于错误报告）

        Returns:
            (是否通过, 错误信息)
        """
        try:
            compile(code, filename, 'exec')
            return True, ""
        except SyntaxError as e:
            return False, f"语法错误: {e}"

    def check_file_syntax(self, file_path: str) -> Tuple[bool, str]:
        """
        检查文件语法

        Args:
            file_path: 文件路径

        Returns:
            (是否通过, 错误信息)
        """
        target = self.project_root / file_path

        if not target.exists():
            return False, f"文件不存在: {file_path}"

        try:
            content = target.read_text(encoding='utf-8')
            return self.check_syntax(content, str(target))
        except Exception as e:
            return False, f"读取文件失败: {e}"

    def check_imports(self, code: str) -> Tuple[bool, List[str]]:
        """
        检查导入是否可用

        Args:
            code: Python代码

        Returns:
            (是否全部可用, 不可用的导入列表)
        """
        missing = []

        try:
            tree = ast.parse(code)
        except SyntaxError:
            return False, ["代码有语法错误，无法分析"]

        # 提取import语句
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    module_name = alias.name.split('.')[0]
                    try:
                        __import__(module_name)
                    except ImportError:
                        missing.append(module_name)

            elif isinstance(node, ast.ImportFrom):
                if node.module:
                    module_name = node.module.split('.')[0]
                    try:
                        __import__(module_name)
                    except ImportError:
                        missing.append(module_name)

        return len(missing) == 0, missing

    def test_run_file(self, file_path: str, args: List[str] = None) -> Dict[str, Any]:
        """
        运行Python文件测试

        Args:
            file_path: 文件路径
            args: 命令行参数

        Returns:
            测试结果
        """
        target = self.project_root / file_path

        if not target.exists():
            return {'success': False, 'error': f"文件不存在: {file_path}"}

        cmd = [sys.executable, str(target)]
        if args:
            cmd.extend(args)

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
                cwd=str(self.project_root)
            )

            return {
                'success': result.returncode == 0,
                'returncode': result.returncode,
                'stdout': result.stdout,
                'stderr': result.stderr
            }

        except subprocess.TimeoutExpired:
            return {'success': False, 'error': '执行超时'}
        except Exception as e:
            return {'success': False, 'error': str(e)}

    def run_tests(self, test_path: str = "tests") -> Dict[str, Any]:
        """
        运行单元测试

        Args:
            test_path: 测试目录或文件路径

        Returns:
            测试结果
        """
        target = self.project_root / test_path

        if not target.exists():
            return {'success': False, 'error': f"测试路径不存在: {test_path}"}

        try:
            # 尝试使用pytest
            result = subprocess.run(
                [sys.executable, "-m", "pytest", str(target), "-v"],
                capture_output=True,
                text=True,
                timeout=60,
                cwd=str(self.project_root)
            )

            return {
                'success': result.returncode == 0,
                'stdout': result.stdout,
                'stderr': result.stderr,
                'returncode': result.returncode
            }

        except FileNotFoundError:
            # 没有pytest，尝试unittest
            try:
                result = subprocess.run(
                    [sys.executable, "-m", "unittest", "discover", "-s", str(target)],
                    capture_output=True,
                    text=True,
                    timeout=60,
                    cwd=str(self.project_root)
                )

                return {
                    'success': result.returncode == 0,
                    'stdout': result.stdout,
                    'stderr': result.stderr,
                    'returncode': result.returncode
                }

            except Exception as e:
                return {'success': False, 'error': str(e)}

        except Exception as e:
            return {'success': False, 'error': str(e)}

    # ==================== 自省模式 ====================

    def introspect_module(self, module_name: str) -> Dict[str, Any]:
        """
        自省模块 - 探索未知库的API

        Args:
            module_name: 模块名称

        Returns:
            模块信息字典
        """
        result = {
            'module': module_name,
            'success': False,
            'exports': [],
            'functions': [],
            'classes': [],
            'doc': ''
        }

        try:
            module = __import__(module_name)
            result['success'] = True

            # 获取导出列表
            if hasattr(module, '__all__'):
                result['exports'] = module.__all__
            else:
                result['exports'] = [name for name in dir(module)
                                   if not name.startswith('_')]

            # 获取函数
            for name in dir(module):
                obj = getattr(module, name, None)
                if callable(obj) and not name.startswith('_'):
                    try:
                        sig = inspect.signature(obj)
                        result['functions'].append({
                            'name': name,
                            'signature': str(sig),
                            'doc': inspect.getdoc(obj)[:100] if inspect.getdoc(obj) else ''
                        })
                    except:
                        result['functions'].append({
                            'name': name,
                            'signature': '()',
                            'doc': ''
                        })

            # 获取类
            for name in dir(module):
                obj = getattr(module, name, None)
                if inspect.isclass(obj) and not name.startswith('_'):
                    # 获取类的公共方法
                    methods = [m for m in dir(obj) if not m.startswith('_') and callable(getattr(obj, m, None))]
                    result['classes'].append({
                        'name': name,
                        'doc': inspect.getdoc(obj)[:100] if inspect.getdoc(obj) else '',
                        'methods': methods[:10]
                    })

            # 获取模块文档
            result['doc'] = inspect.getdoc(module)[:200] if inspect.getdoc(module) else ''

        except ImportError as e:
            result['error'] = f"无法导入模块: {e}"
        except Exception as e:
            result['error'] = f"自省失败: {e}"

        return result

    def introspect_function(self, func_path: str) -> Dict[str, Any]:
        """
        自省函数 - 查看函数签名和文档

        Args:
            func_path: 函数路径，如 "os.path.join"

        Returns:
            函数信息字典
        """
        result = {
            'path': func_path,
            'success': False,
            'signature': '',
            'doc': '',
            'source': ''
        }

        try:
            # 解析路径
            parts = func_path.split('.')
            module_name = parts[0]
            func_name = parts[-1] if len(parts) > 1 else parts[0]

            # 导入模块
            if len(parts) > 1:
                module = __import__(module_name, fromlist=parts[1:])
                obj = getattr(module, func_name)
            else:
                obj = __import__(func_name)

            result['success'] = True

            # 获取签名
            try:
                result['signature'] = str(inspect.signature(obj))
            except:
                result['signature'] = '(无法获取签名)'

            # 获取文档
            result['doc'] = inspect.getdoc(obj) or '无文档'

            # 获取源码（如果可能）
            try:
                result['source'] = inspect.getsource(obj)[:500]
            except:
                result['source'] = '(无法获取源码)'

        except Exception as e:
            result['error'] = str(e)

        return result

    def explore_library(self, module_name: str) -> str:
        """
        探索库并生成报告（给大模型用）

        Args:
            module_name: 模块名称

        Returns:
            格式化的报告
        """
        info = self.introspect_module(module_name)

        if not info['success']:
            return f"无法探索模块 {module_name}: {info.get('error', '未知错误')}"

        lines = [f"=== 模块: {module_name} ==="]

        if info['doc']:
            lines.append(f"\n模块说明:\n{info['doc']}")

        if info['classes']:
            lines.append("\n=== 类 ===")
            for cls in info['classes'][:5]:
                lines.append(f"\n类: {cls['name']}")
                if cls['doc']:
                    lines.append(f"  说明: {cls['doc']}")
                if cls['methods']:
                    lines.append(f"  方法: {', '.join(cls['methods'])}")

        if info['functions']:
            lines.append("\n=== 函数 ===")
            for func in info['functions'][:10]:
                lines.append(f"\n{func['name']}{func['signature']}")
                if func['doc']:
                    lines.append(f"  {func['doc']}")

        return "\n".join(lines)


def debug_file(file_path: str, project_root: str = ".") -> Dict[str, Any]:
    """
    便捷函数：调试文件

    Args:
        file_path: 文件路径
        project_root: 项目根目录

    Returns:
        调试结果
    """
    debugger = Debugger(project_root)

    # 语法检查
    syntax_ok, syntax_error = debugger.check_file_syntax(file_path)

    result = {
        'file': file_path,
        'syntax_ok': syntax_ok,
        'syntax_error': syntax_error
    }

    # 如果语法正确，尝试导入检查
    if syntax_ok:
        content = Path(project_root) / file_path
        content_str = content.read_text(encoding='utf-8')
        imports_ok, missing = debugger.check_imports(content_str)
        result['imports_ok'] = imports_ok
        result['missing_imports'] = missing

    return result


if __name__ == '__main__':
    # 测试自省模式
    print("=== 自省模式测试 ===")

    debugger = Debugger(".")

    # 探索requests库
    print("\n探索 requests 库:")
    print(debugger.explore_library('requests'))
