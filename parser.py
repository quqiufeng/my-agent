#!/usr/bin/env python3
"""
Parser 模块 - 解析 #指令 #end 标签格式
将 API 返回的文本解析为结构化指令，交给 executor 执行
"""

import re
from typing import List, Dict, Optional


class Parser:
    """指令解析器"""

    # 11 种标签的正则表达式
    PATTERNS = {
        "shell": re.compile(r"#shell\s*(.*?)\s*#end", re.DOTALL | re.IGNORECASE),
        "code": re.compile(r"#code\s*(.*?)\s*#end", re.DOTALL | re.IGNORECASE),
        "debug": re.compile(r"#debug\s*(.*?)\s*#end", re.DOTALL | re.IGNORECASE),
        "inspect": re.compile(r"#inspect\s*(.*?)\s*#end", re.DOTALL | re.IGNORECASE),
        "read": re.compile(
            r"#read\s+(\S+)(?:\s+(\d+)(?::(\d+))?)?\s*#end", re.DOTALL | re.IGNORECASE
        ),
        "file": re.compile(r"#file\s+(\S+)\s*(.*?)\s*#end", re.DOTALL | re.IGNORECASE),
        "dir": re.compile(r"#dir\s+(\S+)\s*#end", re.DOTALL | re.IGNORECASE),
        "log": re.compile(
            r"#log\s+(\S+)(?:\s+(\d+))?\s*(.*?)\s*#end", re.DOTALL | re.IGNORECASE
        ),
        "edit": re.compile(
            r"#edit\s+(\S+)\s+(\d+)(?::(\d+))?\s*(.*?)\s*#end",
            re.DOTALL | re.IGNORECASE,
        ),
        "comment": re.compile(
            r"#comment\s+(\S+)\s+([\d:,]+)\s*#end", re.DOTALL | re.IGNORECASE
        ),
        "delete": re.compile(
            r"#delete\s+(\S+)\s+([\d:,]+)\s*#end", re.DOTALL | re.IGNORECASE
        ),
    }

    def parse(self, response: str) -> List[Dict]:
        """解析 API 响应，提取所有指令"""
        instructions = []
        instructions.extend(self.parse_shell(response))
        instructions.extend(self.parse_code(response))
        instructions.extend(self.parse_debug(response))
        instructions.extend(self.parse_inspect(response))
        instructions.extend(self.parse_read(response))
        instructions.extend(self.parse_file(response))
        instructions.extend(self.parse_dir(response))
        instructions.extend(self.parse_log(response))
        instructions.extend(self.parse_edit(response))
        instructions.extend(self.parse_comment(response))
        instructions.extend(self.parse_delete(response))
        return instructions

    # ========== 11 种标签解析函数 ==========

    def parse_shell(self, text: str) -> List[Dict]:
        """
        功能：执行 Shell 命令
        用途：安装依赖、运行脚本，执行系统命令

        格式: #shell 命令 #end
        示例: #shell pip install requests #end

        返回: [{'type': 'shell', 'content': 'pip install requests'}]
        """
        pattern = self.PATTERNS["shell"]
        results = []
        for match in pattern.finditer(text):
            results.append({"type": "shell", "content": match.group(1).strip()})
        return results

    def parse_code(self, text: str) -> List[Dict]:
        """
        功能：执行 Python 代码
        用途：在本地执行 Python 代码片段，用于测试或计算

        格式: #code Python代码 #end
        示例: #code print('hello') #end

        返回: [{'type': 'code', 'content': "print('hello')"}]
        """
        pattern = self.PATTERNS["code"]
        results = []
        for match in pattern.finditer(text):
            results.append({"type": "code", "content": match.group(1).strip()})
        return results

    def parse_debug(self, text: str) -> List[Dict]:
        """
        功能：调试 Python 代码
        用途：通过 python -c 执行，返回执行结果给大模型，帮助掌握现场情况

        格式: #debug Python代码 #end
        示例: #debug print('hello') #end

        返回: [{'type': 'debug', 'content': "print('hello')"}]
        """
        pattern = self.PATTERNS["debug"]
        results = []
        for match in pattern.finditer(text):
            results.append({"type": "debug", "content": match.group(1).strip()})
        return results

    def parse_inspect(self, text: str) -> List[Dict]:
        """
        功能：自省模块/函数
        用途：获取模块、类、函数的签名和参数，帮助大模型了解未知 API

        格式: #inspect 模块名 #end
        格式: #inspect 模块名,模块名2 #end
        格式: #inspect 模块名.函数名 #end
        示例: #inspect requests #end
        示例: #inspect requests,os,json #end
        示例: #inspect requests.get #end

        返回: [{'type': 'inspect', 'target': 'requests,os,json'}]
        """
        pattern = self.PATTERNS["inspect"]
        results = []
        for match in pattern.finditer(text):
            target = match.group(1).strip()
            results.append({"type": "inspect", "target": target})
        return results

    def parse_read(self, text: str) -> List[Dict]:
        """
        功能：读取文件内容
        用途：查看文件内容，帮助大模型了解现有代码

        格式: #read 文件路径 #end
        格式: #read 文件路径 开始行:结束行 #end
        示例: #read src/main.py #end
        示例: #read src/main.py 10:20 #end

        返回: [{'type': 'read', 'target': 'src/main.py', 'start_line': 10, 'end_line': 20}]
        """
        pattern = self.PATTERNS["read"]
        results = []
        for match in pattern.finditer(text):
            file_path = match.group(1).strip()
            start_line = int(match.group(2)) if match.group(2) else None
            end_line = int(match.group(3)) if match.group(3) else start_line
            results.append(
                {
                    "type": "read",
                    "target": file_path,
                    "start_line": start_line,
                    "end_line": end_line,
                }
            )
        return results

    def parse_file(self, text: str) -> List[Dict]:
        """
        功能：写入文件（整体替换）
        用途：创建新文件或整体替换已有文件内容

        格式: #file 文件路径 内容 #end
        示例: #file src/main.py def main(): pass #end

        返回: [{'type': 'file', 'target': 'src/main.py', 'content': 'def main(): pass'}]
        """
        pattern = self.PATTERNS["file"]
        results = []
        for match in pattern.finditer(text):
            results.append(
                {
                    "type": "file",
                    "target": match.group(1).strip(),
                    "content": match.group(2).strip(),
                }
            )
        return results

    def parse_dir(self, text: str) -> List[Dict]:
        """
        功能：创建目录
        用途：创建目录结构

        格式: #dir 目录路径 #end
        示例: #dir src/utils #end

        返回: [{'type': 'dir', 'target': 'src/utils'}]
        """
        pattern = self.PATTERNS["dir"]
        results = []
        for match in pattern.finditer(text):
            results.append({"type": "dir", "target": match.group(1).strip()})
        return results

    def parse_log(self, text: str) -> List[Dict]:
        """
        功能：添加日志语句
        用途：在指定文件插入日志记录代码

        格式: #log 文件路径 [行号] 日志内容 #end
        示例: #log src/main.py import logging #end
        示例: #log src/main.py 10 logger.info('ok') #end

        返回: [{'type': 'log', 'target': 'src/main.py', 'start_line': None, 'content': '...'}]
        """
        pattern = self.PATTERNS["log"]
        results = []
        for match in pattern.finditer(text):
            file_path = match.group(1).strip()
            line_num = int(match.group(2)) if match.group(2) else None
            log_content = match.group(3).strip()
            results.append(
                {
                    "type": "log",
                    "target": file_path,
                    "start_line": line_num,
                    "content": log_content,
                }
            )
        return results

    def parse_edit(self, text: str) -> List[Dict]:
        """
        功能：修改文件指定行（替换内容）
        用途：修改文件特定行的内容

        格式: #edit 文件路径 起始行[:结束行] 新内容 #end
        示例: #edit src/main.py 10 def new(): pass #end
        示例: #edit src/main.py 10:20 new content #end

        返回: [{'type': 'edit', 'target': 'src/main.py', 'start_line': 10, 'end_line': 10, 'content': '...'}]
        """
        pattern = self.PATTERNS["edit"]
        results = []
        for match in pattern.finditer(text):
            file_path = match.group(1).strip()
            start_line = int(match.group(2))
            end_line = int(match.group(3)) if match.group(3) else start_line
            new_content = match.group(4).strip()
            results.append(
                {
                    "type": "edit",
                    "target": file_path,
                    "start_line": start_line,
                    "end_line": end_line,
                    "content": new_content,
                }
            )
        return results

    def parse_comment(self, text: str) -> List[Dict]:
        """
        功能：注释指定行（调试用）
        用途：将指定行加上 # 注释符，用于临时禁用代码

        格式: #comment 文件路径 行号 #end
        示例: #comment src/main.py 10 #end        注释第10行
        示例: #comment src/main.py 10:20 #end    注释第10-20行

        返回: [{'type': 'comment', 'target': 'src/main.py', 'start_line': 10, 'end_line': 10}]
        """
        pattern = self.PATTERNS["comment"]
        results = []
        for match in pattern.finditer(text):
            file_path = match.group(1).strip()
            line_spec = match.group(2).strip()

            # 解析行号：10 或 10:20
            if ":" in line_spec:
                start_line, end_line = line_spec.split(":")
                start_line = int(start_line)
                end_line = int(end_line)
            else:
                start_line = int(line_spec)
                end_line = int(line_spec)

            results.append(
                {
                    "type": "comment",
                    "target": file_path,
                    "start_line": start_line,
                    "end_line": end_line,
                }
            )
        return results

    def parse_delete(self, text: str) -> List[Dict]:
        """
        功能：删除指定行
        用途：删除文件中的指定行

        格式: #delete 文件路径 行号 #end
        示例: #delete src/main.py 10 #end        删除第10行
        示例: #delete src/main.py 10:20 #end    删除第10-20行

        返回: [{'type': 'delete', 'target': 'src/main.py', 'start_line': 10, 'end_line': 10}]
        """
        pattern = self.PATTERNS["delete"]
        results = []
        for match in pattern.finditer(text):
            file_path = match.group(1).strip()
            line_spec = match.group(2).strip()

            # 解析行号：10 或 10:20
            if ":" in line_spec:
                start_line, end_line = line_spec.split(":")
                start_line = int(start_line)
                end_line = int(end_line)
            else:
                start_line = int(line_spec)
                end_line = int(line_spec)

            results.append(
                {
                    "type": "delete",
                    "target": file_path,
                    "start_line": start_line,
                    "end_line": end_line,
                }
            )
        return results

    def extract_tags(self, text: str) -> List[str]:
        """提取所有标签类型（用于调试）"""
        tags = []
        for tag_type in self.PATTERNS.keys():
            matches = self.PATTERNS[tag_type].findall(text)
            for _ in matches:
                tags.append(f"#{tag_type}")
        return tags


def parse_response(text: str) -> List[Dict]:
    """便捷函数：解析 API 响应"""
    parser = Parser()
    return parser.parse(text)


if __name__ == "__main__":
    # 测试
    test_text = """
    #shell
    pip install requests
    #end

    #file src/main.py
    def main():
        print("hello")
    #end

    #dir src/utils
    #end

    #log src/main.py
    import logging
    #end

    #edit src/main.py 10
    def new_func():
        pass
    #end

    #comment src/main.py 10:20
    #end

    #delete src/main.py 5,10
    #end
    """

    print("=== Parser 测试 ===\n")
    results = parse_response(test_text)
    for i, r in enumerate(results, 1):
        print(f"{i}. {r}")
