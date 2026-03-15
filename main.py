#!/usr/bin/env python3
"""
命令行交互模式
用户输入请求 → 发送到远程API → 返回结果 → 等待下一个输入

命令格式：
- 直接执行：!shell 命令
- AI 处理：普通文本，会发送到远程 API
"""

import sys
import os
import subprocess

sys.path.insert(0, os.path.dirname(__file__))

from prompt import build_user_prompt
from api import chat
from parser import Parser
from executor import Executor


def is_direct_shell_command(user_input: str) -> bool:
    """判断是否为直接执行的 shell 命令"""
    return user_input.startswith("!")


SAFE_SHELL_COMMANDS = {
    "ls",
    "pwd",
    "cd",
    "cat",
    "head",
    "tail",
    "grep",
    "find",
    "tree",
    "git status",
    "git log",
    "git diff",
    "which",
    "whereis",
    "file",
    "stat",
    "wc",
    "sort",
    "uniq",
    "awk",
    "sed",
}


def execute_direct_shell(command: str) -> str:
    """直接执行安全的 shell 命令"""
    cmd = command[1:].strip()
    safe = False
    for safe_cmd in SAFE_SHELL_COMMANDS:
        if cmd.startswith(safe_cmd):
            safe = True
            break

    if not safe:
        return f"安全提示：不允许执行此命令，仅支持只读查询类命令（如 ls, pwd, cat, git status 等）"

    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=30,
        )
        output = result.stdout if result.stdout else result.stderr
        return output or "命令执行完成（无输出）"
    except Exception as e:
        return f"执行失败: {e}"


def main():
    print("=" * 50)
    print("AI 编程助手 - 命令行模式")
    print("输入你的需求，按回车执行")
    print("输入 '!shell 命令' 直接执行 shell")
    print("输入 'quit' 或 'exit' 退出")
    print("=" * 50)
    print()

    parser = Parser()
    executor = Executor()

    while True:
        try:
            user_input = input(">>> ").strip()

            if not user_input:
                continue

            if user_input.lower() in ["quit", "exit", "q", "!quit"]:
                print("再见!")
                break

            # 判断是否为直接执行的 shell 命令
            if is_direct_shell_command(user_input):
                print("\n[直接执行 shell 命令...]")
                result = execute_direct_shell(user_input)
                print(result)
                print()
                continue

            # 需要发送到远程 API 处理
            print("\n[正在发送到远程 API...]\n")

            prompt = build_user_prompt(user_input)
            result = chat(
                messages=[{"role": "user", "content": prompt}],
                source="minimax",
                max_tokens=8192,
            )

            print("=" * 50)
            print("API 返回结果:")
            print("=" * 50)
            print(result)
            print()

            # 解析并执行指令
            instructions = parser.parse(result)
            if instructions:
                print("[执行指令...]")
                for instr in instructions:
                    exec_result = executor.execute(instr)
                    print(f"执行结果: {exec_result}")
            elif "[success!]" in result:
                print("[任务完成]")
            print()

        except KeyboardInterrupt:
            print("\n再见!")
            break
        except Exception as e:
            print(f"错误: {e}\n")


if __name__ == "__main__":
    main()
