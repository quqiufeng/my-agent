#!/usr/bin/env python3
"""
AI 编程助手 - 命令行交互模式
"""

import json
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

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

            # 需要发送到远程 API 处理（子进程调用）
            while True:
                print("\n[正在发送到远程 API...]" + "\n", flush=True)

                # 子进程调用，避免阻塞
                proc = subprocess.Popen(
                    [
                        sys.executable,
                        os.path.join(SCRIPT_DIR, "call_api.py"),
                        user_input,
                    ],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
                try:
                    stdout, stderr = proc.communicate(timeout=180)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    print("调用超时", flush=True)
                    break

                if stderr:
                    print(f"错误: {stderr.decode()}", flush=True)
                    break

                if not stdout:
                    print("没有返回结果", flush=True)
                    break

                data = json.loads(stdout.decode())
                result = data["result"]

                print(f"返回结果长度: {len(result)}", flush=True)

                # 写入 debug.log
                with open("debug.log", "w", encoding="utf-8") as f:
                    f.write(result)
                print("已写入 debug.log", flush=True)

                # 解析并执行指令
                try:
                    instructions = parser.parse(result)
                except Exception as e:
                    print(f"解析错误: {e}", flush=True)
                    import traceback

                    traceback.print_exc()
                    break
                if instructions:
                    print("[解析指令...]", flush=True)
                    print(f"instructions: {instructions}", flush=True)

                    # 分离执行类指令和元信息指令
                    exec_instructions = [
                        i
                        for i in instructions
                        if i.get("type") not in ["task", "history"]
                    ]
                    meta_instructions = [
                        i for i in instructions if i.get("type") in ["task", "history"]
                    ]

                    if exec_instructions:
                        print("[执行指令...]", flush=True)
                        exec_results = []
                        for instr in exec_instructions:
                            exec_result = executor.execute(instr)
                            print(f"执行结果: {exec_result}", flush=True)
                            exec_results.append(exec_result["output"])
                        print(flush=True)
                    else:
                        exec_results = []

                    # 构建发送给 API 的提示词（包含执行结果）
                    prompt_with_result = f"{user_input}\n\n--- 上一次执行结果 ---\n{chr(10).join(exec_results)}"
                    print("=== 发送给 API 的提示词 ===", flush=True)
                    print(prompt_with_result, flush=True)
                    print("=== 提示词结束 ===\n", flush=True)
                    break  # stop

                # 有指令执行完，继续循环
                # continue

                # 没有指令，检查是否完成
                if "[success!]" in result:
                    print("[任务完成]", flush=True)
                    break

                # 没有指令也没有 success，询问用户
                user_continue = (
                    input("[是否继续？(y/n) 或输入补充信息] ").strip().lower()
                )
                if user_continue in ["n", "no"]:
                    print("[结束任务]", flush=True)
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
