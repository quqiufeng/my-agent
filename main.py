#!/usr/bin/env python3
"""
AI 编程助手 - 命令行交互模式
"""

import subprocess
from api import chat
from parser import Parser
from executor import Executor
from prompt import build_user_prompt

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


def is_direct_shell_command(command: str) -> bool:
    """判断是否为直接执行的 shell 命令"""
    return command.startswith("!") and not command.startswith("!!")


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
            while True:
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
                    print()
                    # 有指令执行完，继续循环等待下一次 API 调用
                    continue

                # 没有指令，检查是否完成
                if "[success!]" in result:
                    print("[任务完成]")
                    break

                # 没有指令也没有 success，询问用户
                user_continue = (
                    input("[是否继续？(y/n) 或输入补充信息] ").strip().lower()
                )
                if user_continue in ["n", "no"]:
                    print("[结束任务]")
                    break
                elif user_continue in ["y", "yes", ""]:
                    # 继续调用 API
                    continue
                else:
                    # 用户补充了信息，添加到原需求
                    user_input = f"{user_input}\n{user_continue}"
                    continue

        except KeyboardInterrupt:
            print("\n再见!")
            break
        except Exception as e:
            print(f"错误: {e}\n")


if __name__ == "__main__":
    main()
