#!/usr/bin/env python3
"""
Prompt 模块 - 提示词构建
构建每次请求远程大模型时需要的提示词
"""

import os
import sys
from typing import List, Dict, Optional
from dataclasses import dataclass, field

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from scanner import ProjectContext


@dataclass
class ExecutionResult:
    """单次执行结果"""

    type: str
    success: bool
    output: str
    error: str = ""
    timestamp: str = ""


@dataclass
class PromptContext:
    """提示词上下文"""
    project_context: Optional[ProjectContext] = None
    execution_history: List[ExecutionResult] = field(default_factory=list)
    user_task: str = ""
    max_history: int = 10


class PromptBuilder:
    """提示词构建器"""

    def __init__(self, context: PromptContext):
        self.ctx = context

    def build_system_prompt(self) -> str:
        """构建系统提示词"""
        return SYSTEM_PROMPT

    def build_user_prompt(self) -> str:
        """构建用户任务提示词"""
        lines = ["# 本次任务"]

        if self.ctx.user_task:
            lines.append(self.ctx.user_task)

        lines.append("")
        lines.append("请分析现场情况，使用标签指令完成的任务。")
        lines.append("完成所有操作后，直接返回结果，不要使用标签。")

        return "\n".join(lines)


SYSTEM_PROMPT = """你是一个本地 AI 编程助手。

## 你的能力
1. 读写文件、执行命令、分析代码
2. 通过标签指令与本地环境交互
3. 根据执行结果迭代修复问题

## 工作流程
1. 先了解项目现状（使用 #read 读取关键文件）
2. 规划实现方案
3. 使用标签指令执行操作
4. 检查执行结果，根据需要调整
5. 完成任务后直接返回结果

## 重要约束
- 所有操作必须使用标签格式
- 每次只执行少量操作，等待结果后再继续
- 如果执行失败，分析错误原因并修复"""


TAG_DEFINITIONS = """
你可以使用以下 11 种标签指令：

### 1. #shell - 执行 Shell 命令
用途：安装依赖、运行脚本、执行系统命令
格式：`#shell 命令 #end`
示例：`#shell pip install requests #end`

### 2. #code - 执行 Python 代码
用途：在当前进程执行 Python 代码片段
格式：`#code Python代码 #end`
示例：`#code print('hello') #end`

### 3. #debug - 调试 Python 代码
用途：通过 python -c 执行，返回结果给大模型
格式：`#debug Python代码 #end`
示例：`#debug import sys; print(sys.version) #end`

### 4. #inspect - 自省模块/函数
用途：获取模块、类、函数的签名和参数
格式：`#inspect 模块名 #end`
示例：`#inspect requests,os #end`
示例：`#inspect requests.get #end`

### 5. #read - 读取文件内容
用途：查看文件内容，了解现有代码
格式：`#read 文件路径 #end`
示例：`#read src/main.py #end`
示例：`#read src/main.py 10:20 #end`

### 6. #file - 写入文件（整体替换）
用途：创建新文件或整体替换已有文件
格式：`#file 文件路径 内容 #end`
示例：`#file src/main.py def main(): pass #end`

### 7. #dir - 创建目录
用途：创建目录结构
格式：`#dir 目录路径 #end`
示例：`#dir src/utils #end`

### 8. #log - 添加日志语句
用途：在文件插入日志代码
格式：`#log 文件路径 [行号] 日志内容 #end`
示例：`#log src/main.py logger.info('ok') #end`

### 9. #edit - 修改指定行
用途：修改文件特定行的内容
格式：`#edit 文件路径 行号 新内容 #end`
示例：`#edit src/main.py 10 def new(): pass #end`

### 10. #comment - 注释指定行
用途：临时禁用代码
格式：`#comment 文件路径 行号 #end`
示例：`#comment src/main.py 10 #end`

### 11. #delete - 删除指定行
用途：删除文件中的指定行
格式：`#delete 文件路径 行号 #end`
示例：`#delete src/main.py 10 #end`

## 标签使用规则
1. 标签必须成对出现：`#shell ... #end`
2. 可以在同一次回复中使用多个标签
3. 执行结果会返回给你，根据结果决定下一步
4. 完成后不要使用标签，直接返回结果"""



if __name__ == "__main__":
    print("=== Prompt 测试 ===\n")

    messages = build_prompt("给项目添加一个 hello world 脚本")
    print(messages)

