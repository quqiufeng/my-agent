#!/usr/bin/env python3
"""
OpenCode CLI - 主入口
整合所有模块，实现与大模型API的标签指令交互
"""

import os
import sys
import argparse
from pathlib import Path

# 导入所有模块
from api import chat, chat_with_json
from prompt import SYSTEM_PROMPT, build_user_prompt, build_first_prompt, format_progress
from system import get_system_info
from scanner import Scanner
from parser import parse_response
from executor import Executor
from planner import Planner
from debugger import Debugger
from logger import Logger, get_logger


class OpenCode:
    """OpenCode主类"""

    def __init__(self, project_root: str = ".", provider: str = None):
        self.project_root = Path(project_root).absolute()

        # 初始化各模块
        self.scanner = Scanner(self.project_root)
        self.planner = Planner(self.project_root)
        self.executor = Executor(self.project_root)
        self.debugger = Debugger(self.project_root)
        self.logger = Logger(self.project_root)

        # API客户端（延迟初始化）
        self.client = None
        self.provider = provider

    def init_api_client(self, api_key: str = None, provider: str = None, **kwargs):
        """
        初始化API客户端

        Args:
            api_key: API密钥
            provider: 提供商
            **kwargs: 其他参数
        """
        if api_key is None:
            api_key = os.environ.get('LLM_API_KEY')

        if not api_key:
            raise ValueError("请设置 LLM_API_KEY 环境变量或传入 api_key 参数")

        provider = provider or self.provider or 'moonshot'
        self.client = APIClient(api_key=api_key, provider=provider, **kwargs)

    def collect_context(self) -> str:
        """收集项目上下文"""
        sections = [
            get_system_info(self.project_root),
            self.scanner.generate_summary()
        ]
        return "\n\n".join(sections)

    def chat(self, user_requirement: str) -> str:
        """
        与大模型对话

        Args:
            user_requirement: 用户需求

        Returns:
            API响应
        """
        if not self.client:
            raise RuntimeError("请先调用 init_api_client() 初始化API客户端")

        # 收集上下文
        system_context = self.collect_context()

        # 构建消息
        progress_info = self.planner.get_progress_info()

        if progress_info and "尚未开始" not in progress_info:
            # 继续任务
            messages = [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": build_user_prompt(
                    user_requirement=user_requirement,
                    system_info=system_context,
                    project_structure=self.scanner.get_file_tree(),
                    progress_info=progress_info
                )}
            ]
        else:
            # 新任务
            # 启动新任务
            self.planner.start_new_task(user_requirement)

            messages = [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": build_first_prompt(
                    user_requirement=user_requirement,
                    system_info=system_context
                )}
            ]

        # 发送请求
        print("🤔 思考中...")
        response = self.client.chat(messages)
        return response

    def execute_response(self, response: str) -> bool:
        """
        执行API响应中的指令

        Args:
            response: API响应文本

        Returns:
            是否全部成功
        """
        # 解析指令
        instructions = parse_response(response)

        if not instructions:
            print("⚠️ 未解析到指令")
            return False

        print(f"📋 解析到 {len(instructions)} 条指令")

        # 执行指令
        all_success = True
        for i, instruction in enumerate(instructions, 1):
            print(f"\n[{i}/{len(instructions)}] 执行 #{instruction['type']}...")

            result = self.executor.execute(instruction)

            # 记录日志
            if instruction['type'] == 'shell':
                self.logger.log_shell(
                    instruction['content'],
                    result.get('success', False),
                    result.get('output', ''),
                    result.get('error', '')
                )
            elif instruction['type'] == 'file':
                self.logger.log_file(
                    instruction['target'],
                    result.get('success', False),
                    result.get('output', ''),
                    result.get('error', '')
                )
            elif instruction['type'] == 'dir':
                self.logger.log_dir_created(
                    instruction['target'],
                    result.get('success', False),
                    result.get('output', ''),
                    result.get('error', '')
                )
            elif instruction['type'] == 'code':
                self.logger.log_code(
                    instruction['content'],
                    result.get('success', False),
                    result.get('output', ''),
                    result.get('error', '')
                )
            elif instruction['type'] == 'log':
                self.logger.log_log(
                    instruction['target'],
                    result.get('success', False),
                    result.get('output', ''),
                    result.get('error', '')
                )
            elif instruction['type'] == 'edit':
                # 记录edit操作
                start = instruction.get('start_line', 0)
                end = instruction.get('end_line', 0)
                self.logger.logger.info(
                    f"[edit] {instruction['target']} 行 {start}-{end}: "
                    f"{'成功' if result.get('success') else '失败'}"
                )
            elif instruction['type'] == 'comment':
                # 记录comment操作
                start = instruction.get('start_line', 0)
                end = instruction.get('end_line', 0)
                self.logger.logger.info(
                    f"[comment] {instruction['target']} 行 {start}-{end}: "
                    f"{'成功' if result.get('success') else '失败'}"
                )

            # 添加到任务计划
            if instruction['type'] == 'shell':
                self.planner.add_step('shell', instruction['content'])
            elif instruction['type'] == 'file':
                self.planner.add_step('file', instruction['target'], instruction.get('content', ''))
            elif instruction['type'] == 'dir':
                self.planner.add_step('dir', instruction['target'])
            elif instruction['type'] == 'edit':
                lines_info = f"{instruction.get('start_line', 0)}:{instruction.get('end_line', 0)}"
                self.planner.add_step('edit', f"{instruction['target']} ({lines_info})")
            elif instruction['type'] == 'comment':
                lines_info = f"{instruction.get('start_line', 0)}:{instruction.get('end_line', 0)}"
                self.planner.add_step('comment', f"{instruction['target']} ({lines_info})")
            elif instruction['type'] == 'delete':
                # 记录delete操作
                line_spec = instruction.get('line_spec', '')
                self.logger.logger.info(
                    f"[delete] {instruction['target']} 行 {line_spec}: "
                    f"{'成功' if result.get('success') else '失败'}"
                )
                self.planner.add_step('delete', f"{instruction['target']} ({line_spec})")

            # 打印结果
            if result.get('success'):
                print(f"  ✓ 成功")
                if result.get('output'):
                    print(f"    {result['output'][:100]}")
                # 标记完成
                if self.planner.steps:
                    self.planner.mark_completed(self.planner.steps[-1].id, result.get('output', ''))
            else:
                print(f"  ✗ 失败")
                print(f"    {result.get('error', '未知错误')}")
                all_success = False
                break

        return all_success

    def run(self, requirement: str):
        """
        运行完整的任务

        Args:
            requirement: 用户需求
        """
        print("=" * 50)
        print(f"🚀 开始任务: {requirement}")
        print("=" * 50)

        # 与大模型对话
        response = self.chat(requirement)

        print("\n📥 API响应:")
        print("-" * 40)
        print(response[:500] if len(response) > 500 else response)
        print("-" * 40)

        # 执行指令
        success = self.execute_response(response)

        # 打印进度
        print("\n📊 当前进度:")
        print(self.planner.get_progress_info())

        # 打印日志摘要
        print("\n📝 执行日志:")
        print(self.logger.generate_summary())

        if success:
            print("\n✅ 任务执行完成")
        else:
            print("\n⚠️ 任务执行有误，请检查")

    def interactive(self):
        """交互式模式"""
        print("""
╔═══════════════════════════════════════════╗
║         OpenCode CLI - 交互模式           ║
║                                           ║
║  输入你的需求，AI会帮你完成代码编写        ║
║  输入 'quit' 或 'exit' 退出              ║
║  输入 'status' 查看当前进度              ║
║  输入 'logs' 查看执行日志                ║
╚═══════════════════════════════════════════╝
        """)

        while True:
            try:
                user_input = input("\n> ").strip()

                if user_input.lower() in ['quit', 'exit', 'q']:
                    print("👋 再见!")
                    break

                if not user_input:
                    continue

                if user_input.lower() == 'status':
                    print(self.planner.get_progress_info())
                    continue

                if user_input.lower() == 'logs':
                    print(self.logger.generate_summary())
                    continue

                # 执行任务
                self.run(user_input)

            except KeyboardInterrupt:
                print("\n👋 再见!")
                break
            except Exception as e:
                print(f"❌ 错误: {e}")


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="OpenCode CLI - AI代码进化助手")
    parser.add_argument("-r", "--requirement", help="用户需求")
    parser.add_argument("-p", "--provider", default="moonshot",
                       choices=["openai", "moonshot", "deepseek", "anthropic"],
                       help="API提供商")
    parser.add_argument("-k", "--api-key", help="API密钥")
    parser.add_argument("-m", "--model", help="模型名称")
    parser.add_argument("--interactive", "-i", action="store_true",
                       help="交互式模式")
    parser.add_argument("--project", default=".", help="项目根目录")

    args = parser.parse_args()

    # 创建OpenCode实例
    opencode = OpenCode(project_root=args.project, provider=args.provider)

    # 初始化API
    if args.api_key:
        opencode.init_api_client(api_key=args.api_key, model=args.model)
    else:
        # 尝试从环境变量
        if not os.environ.get('LLM_API_KEY'):
            print("⚠️ 请设置 LLM_API_KEY 环境变量或使用 -k 参数")
            print("示例: export LLM_API_KEY='your-api-key'")
            sys.exit(1)
        opencode.init_api_client(model=args.model)

    # 运行
    if args.interactive or not args.requirement:
        opencode.interactive()
    else:
        opencode.run(args.requirement)


if __name__ == "__main__":
    main()
