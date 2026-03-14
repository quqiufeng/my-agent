#!/usr/bin/env python3
"""
Prompt 模块 - 提示词构建
"""

import os
import sys
from typing import List

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)


def str_replace(template: str, **kwargs) -> str:
    """替换模板中的占位符"""
    for key, value in kwargs.items():
        template = template.replace(f"{{{key}}}", str(value))
    return template


# ============ 模板 ============

SYSTEM_TEMPLATE = """你是本地 AI 编程助手。

## 核心能力
- 读写文件，执行shell命令，Python代码
- 使用 #标签指令 与本地环境交互

## 工作流程
1. 收集信息
2. 规划方案  
3. 执行操作
4. 任务列表
5. 验证结果

## 输出规则
- 使用 #指令 内容 #end

## {tag_info}

## {project}

## {task_info}

## {history_info}

## {user_prompt}

## 重要约束
1. 先收集足够信息再动手
2. 每次只执行少量操作
3. 不可执行危害操作"""


# ============ build_* 函数 ============


def build_tag_info() -> str:
    prompt = """### 1. #shell - 执行Shell命令
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
### 12. #task - 任务进度

#shell 命令 #end"""
    return prompt


def build_project(project_root: str = ".") -> str:
    from scanner import Scanner

    scanner = Scanner(project_root)
    ctx = scanner.scan()
    return f"项目: {ctx.name}\n根目录: {project_root}\n\n结构:\n{ctx.structure[:1500]}"


def build_task_info(task_state: str = "") -> str:
    return task_state or "(无任务状态)"


def build_history_info(history: List = None, max_count: int = 5) -> str:
    if not history:
        return "无执行历史"
    lines = []
    for i, h in enumerate(history[-max_count:], 1):
        s = "✅" if h.get("success") else "❌"
        out = h.get("output", "")[:50]
        lines.append(f"{i}. {s} {h.get('type')}: {out}")
    return "\n".join(lines)


def build_user_prompt(task: str) -> str:
    return f"## 本次任务\n{task}\n\n请使用#标签指令完成。"


# ============ 主函数 ============


def build_prompt(
    user_task: str,
    project_root: str = ".",
    task_state: str = "",
    history: List = None,
    max_history: int = 5,
) -> str:
    return str_replace(
        SYSTEM_TEMPLATE,
        tag_info=build_tag_info(),
        project=build_project(project_root),
        task_info=build_task_info(task_state),
        history_info=build_history_info(history, max_history),
        user_prompt=build_user_prompt(user_task),
    )


def build_messages(
    user_task: str,
    project_root: str = ".",
    task_state: str = "",
    history: List = None,
    max_history: int = 5,
) -> List[dict]:
    return [
        {
            "role": "system",
            "content": build_prompt(
                user_task, project_root, task_state, history, max_history
            ),
        },
        {"role": "user", "content": user_task},
    ]


if __name__ == "__main__":
    print(build_prompt("添加hello"))
