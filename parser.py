#!/usr/bin/env python3
"""
Parser模块 - 解析远程API返回的标签指令
支持6种标签: #shell, #code, #file, #dir, #log, #edit
"""

import re
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass


@dataclass
class Instruction:
    """指令数据类"""
    type: str           # shell/code/file/dir/log/edit
    content: str        # 命令/代码/文件内容
    target: str = ""    # 文件路径（file/log/edit/dir需要）
    start_line: int = 0 # 起始行（edit需要）
    end_line: int = 0   # 结束行（edit需要）
    raw: str = ""       # 原始文本


class Parser:
    """标签指令解析器"""

    # 5种标签的正则表达式
    PATTERNS = {
        # #shell 命令 #end
        'shell': re.compile(
            r'#shell\s*(.*?)\s*#end',
            re.DOTALL | re.IGNORECASE
        ),

        # #code 代码 #end
        'code': re.compile(
            r'#code\s*(.*?)\s*#end',
            re.DOTALL | re.IGNORECASE
        ),

        # #file 文件路径 内容 #end
        'file': re.compile(
            r'#file\s+(\S+)\s*(.*?)\s*#end',
            re.DOTALL | re.IGNORECASE
        ),

        # #dir 文件夹路径 #end
        'dir': re.compile(
            r'#dir\s+(\S+)\s*#end',
            re.DOTALL | re.IGNORECASE
        ),

        # #log 文件路径 行号 日志内容 #end
        # 格式: #log src/main.py 10 日志内容 #end (插入到第10行后)
        # 或: #log src/main.py 日志内容 #end (默认插入到文件末尾)
        'log': re.compile(
            r'#log\s+(\S+)(?:\s+(\d+))?\s*(.*?)\s*#end',
            re.DOTALL | re.IGNORECASE
        ),

        # #edit 文件路径 行号 新内容 #end
        # 格式: #edit src/main.py 10:20 新内容 #end
        # 或: #edit src/main.py 10 单行替换
        'edit': re.compile(
            r'#edit\s+(\S+)\s+(\d+)(?::(\d+))?\s*(.*?)\s*#end',
            re.DOTALL | re.IGNORECASE
        ),

        # #comment 文件路径 行号 - 注释指定行
        # 格式: #comment src/main.py 10 #end (注释第10行)
        # 格式: #comment src/main.py 10:20 #end (注释第10-20行)
        # 格式: #comment src/main.py 1,5,10 #end (注释第1,5,10行)
        # 格式: #comment src/main.py 1:5,10,15:20 #end (混合)
        'comment': re.compile(
            r'#comment\s+(\S+)\s+([\d:,]+)\s*#end',
            re.DOTALL | re.IGNORECASE
        ),

        # #delete 文件路径 行号 - 删除指定行
        # 格式: #delete src/main.py 10 #end (删除第10行)
        # 格式: #delete src/main.py 10:20 #end (删除第10-20行)
        # 格式: #delete src/main.py 1,5,10 #end (删除第1,5,10行)
        # 格式: #delete src/main.py 1:5,10,15:20 #end (混合)
        'delete': re.compile(
            r'#delete\s+(\S+)\s+([\d:,]+)\s*#end',
            re.DOTALL | re.IGNORECASE
        ),
    }

    def parse(self, response: str) -> List[Instruction]:
        """
        解析API响应，提取所有指令

        Args:
            response: API返回的原始文本

        Returns:
            指令列表
        """
        instructions = []

        # 按行解析，识别标签类型
        lines = response.split('\n')

        for line in lines:
            line = line.strip()
            if not line or not line.startswith('#'):
                continue

            # 尝试匹配每种标签
            for tag_type, pattern in self.PATTERNS.items():
                match = pattern.search(response)
                if match:
                    if tag_type in ['file', 'log']:
                        # 需要提取文件路径
                        target = match.group(1).strip()
                        content = match.group(2).strip()
                        instructions.append(Instruction(
                            type=tag_type,
                            target=target,
                            content=content,
                            raw=match.group(0)
                        ))
                    elif tag_type == 'dir':
                        # 目录只需要路径
                        target = match.group(1).strip()
                        instructions.append(Instruction(
                            type=tag_type,
                            target=target,
                            content="",
                            raw=match.group(0)
                        ))
                    else:
                        # shell/code
                        content = match.group(1).strip()
                        instructions.append(Instruction(
                            type=tag_type,
                            content=content,
                            raw=match.group(0)
                        ))

                    # 匹配成功后从响应中移除，避免重复
                    response = response.replace(match.group(0), '', 1)
                    break

        return instructions

    def parse_simple(self, response: str) -> List[Dict]:
        """
        简单解析，返回字典列表（兼容旧版本）

        Args:
            response: API响应文本

        Returns:
            指令字典列表
        """
        instructions = []

        # 解析 #shell
        for match in self.PATTERNS['shell'].finditer(response):
            instructions.append({
                'type': 'shell',
                'content': match.group(1).strip()
            })

        # 解析 #code
        for match in self.PATTERNS['code'].finditer(response):
            instructions.append({
                'type': 'code',
                'content': match.group(1).strip()
            })

        # 解析 #file
        for match in self.PATTERNS['file'].finditer(response):
            instructions.append({
                'type': 'file',
                'target': match.group(1).strip(),
                'content': match.group(2).strip()
            })

        # 解析 #dir
        for match in self.PATTERNS['dir'].finditer(response):
            instructions.append({
                'type': 'dir',
                'target': match.group(1).strip()
            })

        # 解析 #log 文件路径 行号 日志内容 #end
        # 格式: #log src/main.py 10 日志内容 #end (插入到第10行后)
        # 或: #log src/main.py 日志内容 #end (默认插入到文件末尾)
        for match in self.PATTERNS['log'].finditer(response):
            file_path = match.group(1).strip()
            line_num = int(match.group(2)) if match.group(2) else None
            log_content = match.group(3).strip()

            instructions.append({
                'type': 'log',
                'target': file_path,
                'start_line': line_num,
                'content': log_content
            })

        # 解析 #edit 文件路径 行号 新内容 #end
        # 格式: #edit src/main.py 10:20 新内容 #end
        # 或: #edit src/main.py 10 单行替换
        for match in self.PATTERNS['edit'].finditer(response):
            file_path = match.group(1).strip()
            start_line = int(match.group(2))
            end_line = int(match.group(3)) if match.group(3) else start_line
            new_content = match.group(4).strip()

            instructions.append({
                'type': 'edit',
                'target': file_path,
                'start_line': start_line,
                'end_line': end_line,
                'content': new_content
            })

        # 解析 #comment 文件路径 行号 #end
        # 格式: #comment src/main.py 10:20 #end
        # 或: #comment src/main.py 10 单行注释
        for match in self.PATTERNS['comment'].finditer(response):
            file_path = match.group(1).strip()
            start_line = int(match.group(2))
            end_line = int(match.group(3)) if match.group(3) else start_line

            instructions.append({
                'type': 'comment',
                'target': file_path,
                'start_line': start_line,
                'end_line': end_line
            })

        # 解析 #delete 文件路径 行号 #end
        # 格式: #delete src/main.py 10 #end (删除第10行)
        # 格式: #delete src/main.py 10:20 #end (删除第10-20行)
        # 格式: #delete src/main.py 1,5,10 #end (删除第1,5,10行)
        # 格式: #delete src/main.py 1:5,10,15:20 #end (混合)
        for match in self.PATTERNS['delete'].finditer(response):
            file_path = match.group(1).strip()
            line_spec = match.group(2).strip()

            instructions.append({
                'type': 'delete',
                'target': file_path,
                'line_spec': line_spec  # 保留原始规格，如 "1,5,10" 或 "10:20"
            })

        return instructions

    def extract_tags(self, response: str) -> List[str]:
        """
        提取所有标签（用于调试）

        Args:
            response: API响应

        Returns:
            标签列表
        """
        tags = []
        for tag_type in self.PATTERNS.keys():
            matches = self.PATTERNS[tag_type].findall(response)
            for _ in matches:
                tags.append(f"#{tag_type}")
        return tags


def parse_response(response: str) -> List[Dict]:
    """
    便捷函数：解析API响应

    Args:
        response: API返回的文本

    Returns:
        指令列表
    """
    parser = Parser()
    return parser.parse_simple(response)


# 测试
if __name__ == '__main__':
    test_response = """
    #shell
    pip install requests
    #end

    #code
    print("hello")
    #end

    #file src/main.py
    def main():
        print("hello world")
    #end

    #dir src/utils
    #end

    #log src/main.py
    import logging
    logger = logging.getLogger(__name__)
    #end

    #edit src/main.py 10
    def new_function():
        return "new"
    #end

    #edit src/main.py 15:20
    class NewClass:
        def __init__(self):
            self.value = 1
    #end
    """

    print("=== Parser 测试 ===")
    result = parse_response(test_response)
    for item in result:
        print(item)
