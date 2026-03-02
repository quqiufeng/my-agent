#!/usr/bin/env python3
"""
Prompt模块 - 定义与远程大模型通信的Prompt模板
包含6种标签原语的使用说明
"""

# ==================== 标签原语定义 ====================

TAG_INSTRUCTIONS = """=== 标签原语协议 ===

你可以通过以下标签指令来操作本地文件系统：

1. #shell - 执行Shell命令
   用途：安装依赖、运行脚本、执行系统命令
   格式：
   #shell
   pip install requests
   #end

2. #code - 执行Python代码
   用途：在本地执行Python代码片段
   格式：
   #code
   import os
   print(os.getcwd())
   #end

3. #file 文件路径 - 写入文件
   用途：创建或更新文件内容（整体替换）
   格式：
   #file src/main.py
   def main():
       print("hello")
   #end

4. #dir 文件夹路径 - 创建目录
   用途：创建目录结构
   格式：
   #dir src/utils
   #end

5. #log 文件路径 行号 - 添加日志语句
   用途：在指定文件中添加日志记录
   格式（插入到指定行后）：
   #log src/server.py 10
   import logging
   logger = logging.getLogger(__name__)
   logger.info("Server started")
   #end

   格式（默认插入到import之后）：
   #log src/server.py
   import logging
   logger = logging.getLogger(__name__)
   logger.info("Server started")
   #end

   说明：
   - 行号从1开始计数
   - 指定行号时，插入到该行之后
   - 不指定行号时，默认插入到import语句之后

6. #edit 文件路径 行号 - 修改文件特定行
   用途：修改文件的特定行（替换指定行范围的内容）
   格式（单行替换）：
   #edit src/main.py 10
   def new_function():
       pass
   #end

   格式（多行替换）：
   #edit src/main.py 10:20
   def new_function():
       print("hello")
       return True
   #end

   说明：
   - 行号从1开始计数
   - 使用 单个行号 表示替换该行
   - 使用 行号:行号 表示替换从起始行到结束行的内容
   - 会自动备份原文件

7. #comment 文件路径 行号 - 注释指定行
   用途：注释指定的代码行（用于调试）
   格式（单行注释）：
   #comment src/main.py 10
   #end

   格式（多行注释）：
   #comment src/main.py 10:20
   #end

   说明：
   - 行号从1开始计数
   - 会在行首添加 # 注释符
   - 会自动备份原文件
   - 调试完成后可用 #edit 恢复

8. #delete 文件路径 行号 - 删除指定行
   用途：删除文件中的指定行
   格式（单行删除）：
   #delete src/main.py 10
   #end

   格式（范围删除）：
   #delete src/main.py 10:20
   #end

   格式（多行删除，用逗号隔开）：
   #delete src/main.py 1,5,10
   #end

   格式（混合删除）：
   #delete src/main.py 1:5,10,15:20
   #end

   说明：
   - 行号从1开始计数
   - 支持单行、范围、多行、混合格式
   - 会自动备份原文件
   - 删除后无法恢复，请谨慎使用

=== 重要规则 ===
- 每个标签必须用 #end 结束
- #file、#log、#edit、#comment、#delete 需要指定文件路径
- #edit、#comment、#delete 需要指定行号
- #log 行号可选，不指定则默认插入到import之后
- #delete 支持多种格式：单行(10)、范围(10:20)、多行(1,5,10)、混合(1:5,10,15:20)
- 一次可以返回多个标签指令
- 请根据当前进度返回合适的指令
"""

# ==================== System Prompt ====================

SYSTEM_PROMPT = f"""你是一个Python代码进化助手。

{TAG_INSTRUCTIONS}

=== 工作流程 ===
1. 了解当前项目状态（系统会告诉你已完成哪些步骤）
2. 根据用户需求规划下一步操作
3. 返回对应的标签指令来执行操作
4. 等待执行结果后继续下一步

请只返回标签指令，不要返回其他内容。
"""

# ==================== User Prompt 模板 ====================

def build_user_prompt(
    user_requirement: str,
    system_info: str,
    project_structure: str,
    progress_info: str
) -> str:
    """
    构建发送给API的用户Prompt

    Args:
        user_requirement: 用户的需求描述
        system_info: 系统环境信息
        project_structure: 项目结构信息
        progress_info: 任务进度信息

    Returns:
        完整的用户Prompt
    """
    prompt = f"""=== 用户需求 ===
{user_requirement}

{progress_info}

{system_info}

{project_structure}

{TAG_INSTRUCTIONS}

请根据当前状态，返回下一步需要执行的标签指令。
"""
    return prompt


def build_first_prompt(user_requirement: str, system_info: str) -> str:
    """
    构建首次请求的Prompt（无进度信息）

    Args:
        user_requirement: 用户需求
        system_info: 系统环境信息

    Returns:
        完整的用户Prompt
    """
    prompt = f"""=== 用户需求 ===
{user_requirement}

{system_info}

{TAG_INSTRUCTIONS}

这是项目的初始状态，请规划需要执行的步骤，并返回第一批标签指令。
"""
    return prompt


# ==================== 进度信息模板 ====================

def format_progress(
    completed_steps: list,
    pending_steps: list,
    current_step: int = None,
    total_steps: int = None
) -> str:
    """
    格式化进度信息

    Args:
        completed_steps: 已完成的步骤列表
        pending_steps: 待完成的步骤列表
        current_step: 当前步骤编号
        total_steps: 总步骤数

    Returns:
        格式化的进度字符串
    """
    if not completed_steps and not pending_steps:
        return "=== 进度 ===\n新任务，尚未开始"

    lines = ["=== 当前进度 ==="]

    if total_steps:
        lines.append(f"步骤: {current_step or 0}/{total_steps}")

    if completed_steps:
        lines.append("\n已完成操作:")
        for i, step in enumerate(completed_steps, 1):
            lines.append(f"  ✓ {step}")

    if pending_steps:
        lines.append("\n待完成操作:")
        for i, step in enumerate(pending_steps, 1):
            lines.append(f"  ○ {step}")

    return "\n".join(lines)


# ==================== 响应处理 ====================

RESPONSE_GUIDE = """
=== 响应格式说明 ===
请只返回标签指令，每行一个标签：
- #shell 命令 #end
- #code 代码 #end
- #file 文件路径 内容 #end
- #dir 文件夹路径 #end
- #log 文件路径 日志内容 #end
"""


if __name__ == '__main__':
    # 测试
    print("=== System Prompt ===")
    print(SYSTEM_PROMPT)
    print("\n=== 进度信息示例 ===")
    print(format_progress(
        completed_steps=["#dir src", "#file src/main.py"],
        pending_steps=["#shell pip install flask", "#file src/server.py"],
        current_step=2,
        total_steps=4
    ))
