#!/usr/bin/env python3
"""Prompt 模块"""

import os, sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)


SYSTEM_TEMPLATE = """你是本地 AI 编程助手。

## {tag_info}

## {project}

## {task_info}

## {history_info}

## {user_prompt}"""


def build_tag_info():
    return """### 1. #shell - 执行Shell命令
### 2. #code - 执行Python代码
### 3. #debug - 调试代码
### 4. #inspect - 自省模块
### 5. #read - 读文件
### 6. #file - 写文件
### 7. #dir - 创建目录
### 8. #log - 添加日志
### 9. #edit - 修改行
### 10. #comment - 注释行
### 11. #delete - 删除行
### 12. #task - 任务进度"""


def build_project():
    from scanner import Scanner

    ctx = Scanner(".").scan()
    return f"项目: {ctx.name}\n结构:\n{ctx.structure[:1500]}"


def build_task_info():
    return "(无任务状态)"


def build_history_info():
    return "无执行历史"


def build_prompt(user_prompt: str) -> str:
    result = SYSTEM_TEMPLATE
    result = result.replace("{tag_info}", build_tag_info())
    result = result.replace("{project}", build_project())
    result = result.replace("{task_info}", build_task_info())
    result = result.replace("{history_info}", build_history_info())
    result = result.replace("{user_prompt}", user_prompt)
    return result


if __name__ == "__main__":
    print(build_prompt("添加hello"))
