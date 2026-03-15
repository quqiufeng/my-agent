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
    "git",
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
    return command.startswith("!") and not command.startswith("!!")


def execute_direct_shell(command: str) -> str:
    cmd = command[1:].strip()
    safe = any(cmd.startswith(s) for s in SAFE_SHELL_COMMANDS)
    if not safe:
        return "安全提示：不允许执行此命令"

    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=30
        )
        return result.stdout or result.stderr or "命令执行完成（无输出）"
    except Exception as e:
        return f"执行失败: {e}"


def main():
    print("=" * 50)
    print("AI 编程助手 - 命令行模式")
    print("输入需求按回车执行，!命令 直接执行shell，quit 退出")
    print("=" * 50 + "\n")

    parser, executor = Parser(), Executor()

    while True:
        try:
            user_input = input(">>> ").strip()
            if not user_input or user_input.lower() in ["quit", "exit", "q", "!quit"]:
                print("再见!")
                break

            if is_direct_shell_command(user_input):
                print("[直接执行 shell 命令...]")
                print(execute_direct_shell(user_input))
                print()
                continue

            while True:
                print("\n[正在发送到远程 API...]\n", flush=True)

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
                    print("调用超时")
                    break

                if stderr:
                    print(f"错误: {stderr.decode()}")
                    break
                if not stdout:
                    print("没有返回结果")
                    break

                result = json.loads(stdout.decode())["result"]
                print(f"返回结果长度: {len(result)}")

                with open("debug.log", "w") as f:
                    f.write(result)
                print("已写入 debug.log")

                try:
                    instructions = parser.parse(result)
                except Exception as e:
                    print(f"解析错误: {e}")
                    import traceback

                    traceback.print_exc()
                    break

                if instructions:
                    print(f"instructions: {instructions[:3]}")  # 只打印前3个

                    exec_instructions = [
                        i
                        for i in instructions
                        if i.get("type") not in ["task", "history"]
                    ]
                    meta_instructions = [
                        i for i in instructions if i.get("type") in ["task", "history"]
                    ]

                    exec_results = []
                    if exec_instructions:
                        print("[执行指令...]")
                        for instr in exec_instructions:
                            r = executor.execute(instr)
                            print(f"执行结果: {r.get('output', '')[:100]}")
                            exec_results.append(r["output"])

                    # 元信息指令也加进去
                    meta_results = []
                    for instr in meta_instructions:
                        r = executor.execute(instr)
                        meta_results.append(r["output"])

                    prompt_with_result = f"{user_input}\n\n--- 上一次执行结果 ---\n{chr(10).join(exec_results + meta_results)}"
                    print("=== 发送给 API 的提示词 ===")
                    print(prompt_with_result[:500])
                    print("=== 提示词结束 ===\n")
                    break

                if "[success!]" in result:
                    print("[任务完成]")
                    break

                user_continue = (
                    input("[是否继续？(y/n) 或输入补充信息] ").strip().lower()
                )
                if user_continue in ["n", "no"]:
                    print("[结束任务]")
                    break
                elif user_continue and user_continue not in ["y", "yes", ""]:
                    user_input = f"{user_input}\n{user_continue}"

        except KeyboardInterrupt:
            print("\n再见!")
            break
        except Exception as e:
            print(f"错误: {e}\n")


if __name__ == "__main__":
    main()
