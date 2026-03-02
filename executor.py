#!/usr/bin/env python3
"""
Executor模块 - 执行标签指令
支持6种操作: #shell, #code, #file, #dir, #log, #edit
"""

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Any
from datetime import datetime


class Executor:
    """指令执行器"""

    def __init__(self, project_root: str = "."):
        self.project_root = Path(project_root).absolute()
        self.backup_dir = self.project_root / ".opencode_backups"
        self.backup_dir.mkdir(exist_ok=True)

        # 执行历史
        self.execution_history: List[Dict] = []

    def execute_shell(self, command: str, timeout: int = 60) -> Dict[str, Any]:
        """
        执行Shell命令

        Args:
            command: 要执行的命令
            timeout: 超时时间（秒）

        Returns:
            执行结果字典
        """
        result = {
            'type': 'shell',
            'command': command,
            'success': False,
            'output': '',
            'error': '',
            'timestamp': datetime.now().isoformat()
        }

        try:
            # 使用shell执行
            process = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=str(self.project_root)
            )

            result['success'] = process.returncode == 0
            result['output'] = process.stdout
            result['error'] = process.stderr
            result['returncode'] = process.returncode

        except subprocess.TimeoutExpired:
            result['error'] = f"命令执行超时（{timeout}秒）"
        except Exception as e:
            result['error'] = str(e)

        self.execution_history.append(result)
        return result

    def execute_code(self, code: str) -> Dict[str, Any]:
        """
        执行Python代码

        Args:
            code: 要执行的Python代码

        Returns:
            执行结果字典
        """
        result = {
            'type': 'code',
            'code': code,
            'success': False,
            'output': '',
            'error': '',
            'timestamp': datetime.now().isoformat()
        }

        try:
            # 捕获输出
            old_stdout = sys.stdout
            old_stderr = sys.stderr

            from io import StringIO
            stdout_capture = StringIO()
            stderr_capture = StringIO()

            sys.stdout = stdout_capture
            sys.stderr = stderr_capture

            # 执行代码
            exec(code, {'__name__': '__main__'})

            sys.stdout = old_stdout
            sys.stderr = old_stderr

            result['success'] = True
            result['output'] = stdout_capture.getvalue()
            result['error'] = stderr_capture.getvalue()

        except Exception as e:
            result['error'] = f"{type(e).__name__}: {e}"

        self.execution_history.append(result)
        return result

    def _backup_file(self, file_path: Path) -> Optional[Path]:
        """
        备份文件

        Args:
            file_path: 文件路径

        Returns:
            备份文件路径
        """
        if not file_path.exists():
            return None

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_name = f"{file_path.name}.{timestamp}.bak"
        backup_path = self.backup_dir / backup_name

        backup_path.write_text(file_path.read_text(encoding='utf-8'))
        return backup_path

    def execute_file(self, file_path: str, content: str) -> Dict[str, Any]:
        """
        写入文件

        Args:
            file_path: 文件路径
            content: 文件内容

        Returns:
            执行结果字典
        """
        result = {
            'type': 'file',
            'target': file_path,
            'success': False,
            'output': '',
            'error': '',
            'timestamp': datetime.now().isoformat()
        }

        try:
            target_path = self.project_root / file_path

            # 备份已存在的文件
            if target_path.exists():
                backup = self._backup_file(target_path)
                result['backup'] = str(backup)

            # 确保父目录存在
            target_path.parent.mkdir(parents=True, exist_ok=True)

            # 写入内容
            target_path.write_text(content, encoding='utf-8')

            result['success'] = True
            result['output'] = f"文件已写入: {file_path}"

        except Exception as e:
            result['error'] = str(e)

        self.execution_history.append(result)
        return result

    def execute_dir(self, dir_path: str) -> Dict[str, Any]:
        """
        创建目录

        Args:
            dir_path: 目录路径

        Returns:
            执行结果字典
        """
        result = {
            'type': 'dir',
            'target': dir_path,
            'success': False,
            'output': '',
            'error': '',
            'timestamp': datetime.now().isoformat()
        }

        try:
            target_path = self.project_root / dir_path

            # 创建目录
            target_path.mkdir(parents=True, exist_ok=True)

            result['success'] = True
            result['output'] = f"目录已创建: {dir_path}"

        except Exception as e:
            result['error'] = str(e)

        self.execution_history.append(result)
        return result

    def execute_log(self, file_path: str, log_code: str, insert_line: int = None) -> Dict[str, Any]:
        """
        添加日志语句到文件

        Args:
            file_path: 文件路径
            log_code: 日志代码
            insert_line: 插入行号（1-based），None表示默认插入位置（import之后）

        Returns:
            执行结果字典
        """
        result = {
            'type': 'log',
            'target': file_path,
            'success': False,
            'output': '',
            'error': '',
            'timestamp': datetime.now().isoformat()
        }

        try:
            target_path = self.project_root / file_path

            if not target_path.exists():
                result['error'] = f"文件不存在: {file_path}"
                return result

            # 读取原文件
            content = target_path.read_text(encoding='utf-8')

            # 备份
            backup = self._backup_file(target_path)
            result['backup'] = str(backup)

            lines = content.split('\n')

            # 确定插入位置
            if insert_line is not None:
                # 指定了行号，插入到该行之后
                if insert_line < 1 or insert_line > len(lines):
                    result['error'] = f"插入行号 {insert_line} 超出文件范围 (1-{len(lines)})"
                    return result
                insert_pos = insert_line
            else:
                # 未指定行号，默认插入到import之后
                insert_pos = 0
                for i, line in enumerate(lines):
                    if line.strip().startswith('import ') or line.strip().startswith('from '):
                        insert_pos = i + 1

            # 插入日志代码
            log_lines = log_code.split('\n')
            lines.insert(insert_pos, '')
            lines.insert(insert_pos + 1, '# 日志语句（由OpenCode添加）')
            for log_line in log_lines:
                lines.insert(insert_pos + 2, log_line)

            # 写回文件
            target_path.write_text('\n'.join(lines), encoding='utf-8')

            if insert_line is not None:
                result['output'] = f"日志语句已插入到 {file_path} 第 {insert_line} 行后"
            else:
                result['output'] = f"日志语句已添加到 {file_path}"

        except Exception as e:
            result['error'] = str(e)

        self.execution_history.append(result)
        return result

    def execute_edit(self, file_path: str, start_line: int, end_line: int, new_content: str) -> Dict[str, Any]:
        """
        修改文件的特定行

        Args:
            file_path: 文件路径
            start_line: 起始行号（1-based）
            end_line: 结束行号（1-based）
            new_content: 新的内容

        Returns:
            执行结果字典
        """
        result = {
            'type': 'edit',
            'target': file_path,
            'success': False,
            'output': '',
            'error': '',
            'timestamp': datetime.now().isoformat()
        }

        try:
            target_path = self.project_root / file_path

            if not target_path.exists():
                result['error'] = f"文件不存在: {file_path}"
                return result

            # 读取原文件
            lines = target_path.read_text(encoding='utf-8').split('\n')

            # 验证行号范围
            if start_line < 1 or start_line > len(lines):
                result['error'] = f"起始行号 {start_line} 超出文件范围 (1-{len(lines)})"
                return result

            if end_line < start_line or end_line > len(lines):
                result['error'] = f"结束行号 {end_line} 超出文件范围或小于起始行"
                return result

            # 备份
            backup = self._backup_file(target_path)
            result['backup'] = str(backup)

            # 转换为0-based索引
            start_idx = start_line - 1
            end_idx = end_line  # 不包括end_line这一行

            # 替换内容
            new_lines = new_content.split('\n')

            # 如果新内容末尾没有换行，需要特殊处理
            if new_content.endswith('\n'):
                new_lines = new_lines[:-1] if new_lines else []

            # 执行替换
            modified_lines = lines[:start_idx] + new_lines + lines[end_idx:]

            # 写回文件
            target_path.write_text('\n'.join(modified_lines), encoding='utf-8')

            result['success'] = True
            result['output'] = f"已修改 {file_path} 第 {start_line}-{end_line} 行"

        except Exception as e:
            result['error'] = str(e)

        self.execution_history.append(result)
        return result

    def execute_comment(self, file_path: str, start_line: int, end_line: int) -> Dict[str, Any]:
        """
        注释文件的特定行

        Args:
            file_path: 文件路径
            start_line: 起始行号（1-based）
            end_line: 结束行号（1-based）

        Returns:
            执行结果字典
        """
        result = {
            'type': 'comment',
            'target': file_path,
            'success': False,
            'output': '',
            'error': '',
            'timestamp': datetime.now().isoformat()
        }

        try:
            target_path = self.project_root / file_path

            if not target_path.exists():
                result['error'] = f"文件不存在: {file_path}"
                return result

            # 读取原文件
            lines = target_path.read_text(encoding='utf-8').split('\n')

            # 验证行号范围
            if start_line < 1 or start_line > len(lines):
                result['error'] = f"起始行号 {start_line} 超出文件范围 (1-{len(lines)})"
                return result

            if end_line < start_line or end_line > len(lines):
                result['error'] = f"结束行号 {end_line} 超出文件范围或小于起始行"
                return result

            # 备份
            backup = self._backup_file(target_path)
            result['backup'] = str(backup)

            # 注释指定行（添加 # 前缀）
            for i in range(start_line - 1, end_line):
                line = lines[i]
                # 如果行以空格开头，插在第一个空格后；否则直接在行首添加 #
                if line.strip() and not line.strip().startswith('#'):
                    if line.startswith(' ') or line.startswith('\t'):
                        # 找到第一个非空白字符的位置
                        for j, char in enumerate(line):
                            if char not in (' ', '\t'):
                                lines[i] = line[:j] + '# ' + line[j:]
                                break
                    else:
                        lines[i] = '# ' + line

            # 写回文件
            target_path.write_text('\n'.join(lines), encoding='utf-8')

            result['success'] = True
            result['output'] = f"已注释 {file_path} 第 {start_line}-{end_line} 行"

        except Exception as e:
            result['error'] = str(e)

        self.execution_history.append(result)
        return result

    def _parse_line_spec(self, line_spec: str) -> set:
        """
        解析行号规格，返回要删除的行号集合

        Args:
            line_spec: 行号规格，如 "1,5,10" 或 "10:20" 或 "1:5,10,15:20"

        Returns:
            行号集合
        """
        lines_to_delete = set()
        parts = line_spec.split(',')

        for part in parts:
            part = part.strip()
            if ':' in part:
                # 范围，如 "10:20"
                start, end = part.split(':')
                lines_to_delete.update(range(int(start), int(end) + 1))
            else:
                # 单行
                lines_to_delete.add(int(part))

        return lines_to_delete

    def execute_delete(self, file_path: str, line_spec: str) -> Dict[str, Any]:
        """
        删除文件的指定行

        Args:
            file_path: 文件路径
            line_spec: 行号规格，如 "1,5,10" 或 "10:20" 或 "1:5,10,15:20"

        Returns:
            执行结果字典
        """
        result = {
            'type': 'delete',
            'target': file_path,
            'success': False,
            'output': '',
            'error': '',
            'timestamp': datetime.now().isoformat()
        }

        try:
            target_path = self.project_root / file_path

            if not target_path.exists():
                result['error'] = f"文件不存在: {file_path}"
                return result

            # 读取原文件
            lines = target_path.read_text(encoding='utf-8').split('\n')

            # 解析要删除的行号
            lines_to_delete = self._parse_line_spec(line_spec)

            # 验证行号范围
            max_line = len(lines)
            invalid_lines = [l for l in lines_to_delete if l < 1 or l > max_line]
            if invalid_lines:
                result['error'] = f"行号 {invalid_lines} 超出文件范围 (1-{max_line})"
                return result

            # 备份
            backup = self._backup_file(target_path)
            result['backup'] = str(backup)

            # 删除指定行（注意：行号从1开始，列表索引从0开始）
            new_lines = [line for i, line in enumerate(lines, 1) if i not in lines_to_delete]

            # 写回文件
            target_path.write_text('\n'.join(new_lines), encoding='utf-8')

            result['success'] = True
            result['output'] = f"已删除 {file_path} 第 {line_spec} 行（共 {len(lines_to_delete)} 行）"

        except Exception as e:
            result['error'] = str(e)

        self.execution_history.append(result)
        return result

    def execute(self, instruction: Dict) -> Dict[str, Any]:
        """
        执行单条指令（统一入口）

        Args:
            instruction: 指令字典

        Returns:
            执行结果
        """
        handler_map = {
            'shell': lambda: self.execute_shell(instruction['content']),
            'code': lambda: self.execute_code(instruction['content']),
            'file': lambda: self.execute_file(instruction['target'], instruction['content']),
            'dir': lambda: self.execute_dir(instruction['target']),
            'log': lambda: self.execute_log(
                instruction['target'],
                instruction['content'],
                instruction.get('start_line')
            ),
            'edit': lambda: self.execute_edit(
                instruction['target'],
                instruction.get('start_line', 0),
                instruction.get('end_line', 0),
                instruction['content']
            ),
            'comment': lambda: self.execute_comment(
                instruction['target'],
                instruction.get('start_line', 0),
                instruction.get('end_line', 0)
            ),
            'delete': lambda: self.execute_delete(
                instruction['target'],
                instruction.get('line_spec', '')
            ),
        }

        instruction_type = instruction.get('type')
        if instruction_type in handler_map:
            return handler_map[instruction_type]()

        return {
            'success': False,
            'error': f"未知指令类型: {instruction_type}"
        }

    def execute_batch(self, instructions: List[Dict]) -> List[Dict]:
        """
        批量执行指令

        Args:
            instructions: 指令列表

        Returns:
            结果列表
        """
        results = []
        for instruction in instructions:
            result = self.execute(instruction)
            results.append(result)

            # 如果失败，停止执行
            if not result.get('success', False):
                print(f"执行失败: {result.get('error')}")
                break

        return results

    def rollback_last(self) -> bool:
        """
        回滚上一步操作

        Returns:
            是否成功
        """
        if not self.execution_history:
            print("没有可回滚的操作")
            return False

        last = self.execution_history[-1]

        if last['type'] == 'file' and 'backup' in last:
            # 恢复备份文件
            target = self.project_root / last['target']
            backup = Path(last['backup'])

            if backup.exists():
                target.write_text(backup.read_text())
                print(f"已回滚: {last['target']}")
                return True

        print("当前操作不支持回滚")
        return False


def execute_instructions(instructions: List[Dict], project_root: str = ".") -> List[Dict]:
    """
    便捷函数：执行指令列表

    Args:
        instructions: 指令列表
        project_root: 项目根目录

    Returns:
        执行结果列表
    """
    executor = Executor(project_root)
    return executor.execute_batch(instructions)


if __name__ == '__main__':
    # 测试
    print("=== Executor 测试 ===")

    # 测试执行file指令
    executor = Executor(".")
    result = executor.execute_file("test_demo.py", "# Demo file\nprint('hello')")
    print(result)
