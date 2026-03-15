#!/usr/bin/env python3
"""
Prompt 模块 - 提示词构建
构建每次请求远程大模型时需要的提示词

调试方法：
```python
import sys
sys.path.insert(0, '.')
from prompt import build_user_prompt
result = build_user_prompt('生成一个python版本的红黑树')
print(result)
```
"""

import ast
import os
import platform
import subprocess
import sys
from typing import List

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)


class PromptBuilder:
    """提示词构建器"""

    def __init__(self, user_prompt: str):
        self.user_prompt = user_prompt

    def build(self) -> str:
        return build_user_prompt(self.user_prompt)


def build_tag_info(prompt: str) -> str:
    system_prompt = """
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
格式：`#file file:文件路径 内容 #end`
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

### 11. #task - 任务进度表
用途：显示任务进度表，包括任务完成情况
格式：`#task 任务名 完成状态 #end`（必须加 #end）
示例：`#task 新建一个文件 完成 #end`
      #task 实现插入操作 进行中 #end

### 12. #history - 历史信息
用途：需要保留的历史信息，需要你自己维护。用这个信息维护上下文会话信息,发给客户端的该信息会原样返回。
格式：`#history 需要保留的上下文信息  #end`
示例：`#history 当前操作系统是ubuntu,需要进一步获得python版本信息 #end`


## 标签使用规则
1. 所有标签必须成对出现：必须加 `#end` 结束，否则不会被解析
2. 格式：`#标签 命令 #end`
3. 如果同类标签出现多次，可以合并成一个标签包裹多行内容,
   比如三对 #task #end 标签可以合并成一对 #task #end 但是里面内容是 3行。
4. 可以在同一次回复中使用多个标签,如果多个标签内容都比短，按上一条执行。
5. 执行结果会返回给你，根据结果决定下一步。
6. 标签内的内容 不得危害本地环境，包括操作系统和不得下载与项目无关的文件。
7. #file 标签 权重要比 #code 高,#file标签用于创建py脚本必须严格按照标签格式来,需要有#end标签结束。
8. 大段代码应该用 #file #end 创建 py 脚本，然后用 #shell #end 执行 python -c 代码测试。
9. !!!!非常重要：每个标签都必须有对应的 #end 结束，没有 #end 的一律不会被执行。"""

    return prompt.replace("{tag_info}", system_prompt or "未提供项目信息")


def build_project_info(prompt: str, info: str = "") -> str:
    def get_functions_and_classes(file_path: str) -> list[str]:
        results = []
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                source = f.read()
                tree = ast.parse(source, filename=file_path)

            for node in ast.walk(tree):
                if isinstance(node, ast.ClassDef):
                    docstring = ast.get_docstring(node)
                    methods = [
                        n.name
                        for n in node.body
                        if isinstance(n, ast.FunctionDef) and not n.name.startswith("_")
                    ]
                    if methods:
                        results.append(f"class {node.name}: {', '.join(methods)}")
                        if docstring:
                            results.append(f"  # {docstring}")
                    else:
                        results.append(f"class {node.name}")
                        if docstring:
                            results.append(f"  # {docstring}")
                elif isinstance(node, ast.FunctionDef) and not node.name.startswith(
                    "_"
                ):
                    args = [arg.arg for arg in node.args.args]
                    docstring = ast.get_docstring(node)
                    line = f"{node.name}({', '.join(args)})"
                    if docstring:
                        first_line = docstring.split("\n")[0].strip()
                        line += f"  # {first_line}"
                    results.append(line)
        except Exception:
            pass
        return results

    py_files = [
        f
        for f in os.listdir(SCRIPT_DIR)
        if f.endswith(".py") and not f.startswith("__")
    ]

    project_info = []

    # 添加目录树
    def generate_tree(
        path: str, prefix: str = "", max_depth: int = 2, current_depth: int = 0
    ) -> list[str]:
        if current_depth >= max_depth:
            return []
        lines = []
        try:
            entries = sorted(
                os.listdir(path),
                key=lambda x: (not os.path.isdir(os.path.join(path, x)), x),
            )
            for i, entry in enumerate(entries):
                if entry.startswith(".") or entry == "__pycache__":
                    continue
                full_path = os.path.join(path, entry)
                is_last = i == len(entries) - 1
                connector = "└── " if is_last else "├── "
                lines.append(prefix + connector + entry)
                if os.path.isdir(full_path):
                    extension = "    " if is_last else "│   "
                    lines.extend(
                        generate_tree(
                            full_path, prefix + extension, max_depth, current_depth + 1
                        )
                    )
        except Exception:
            pass
        return lines

    try:
        result = subprocess.run(
            ["tree", "-L", "2", "-I", "__pycache__|*.pyc|.git"],
            capture_output=True,
            text=True,
            timeout=10,
            cwd=SCRIPT_DIR,
        )
        if result.returncode == 0:
            project_info.append("## 项目目录结构")
            project_info.append(result.stdout)
        else:
            raise Exception("tree command failed")
    except Exception:
        project_info.append("## 项目目录结构")
        project_info.extend(generate_tree(SCRIPT_DIR))

    # 添加脚本函数信息（每个文件最多5个）
    for py_file in py_files:
        file_path = os.path.join(SCRIPT_DIR, py_file)
        items = get_functions_and_classes(file_path)[:5]
        if items:
            project_info.append(f"## ./{py_file}")
            project_info.extend(items)

    info = "\n".join(project_info) if project_info else "未提供项目信息"
    return prompt.replace("{project_info}", info)


def build_user_prompt_content(prompt: str, user_prompt: str = "") -> str:
    return prompt.replace("{user_prompt}", user_prompt or "未提供用户请求")


def build_task_info(prompt: str, info: str = "") -> str:
    return prompt.replace("{task_info}", info or "暂无任务进度")


def build_history_info(prompt: str, info: str = "") -> str:
    return prompt.replace("{history_info}", info or "暂无历史上下文信息")


def build_system_info(prompt: str, project_root: str = "", info: str = "") -> str:
    def get_path(cmd: str) -> str:
        try:
            result = subprocess.run(
                ["which", cmd],
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except Exception:
            pass
        return "未安装"

    def get_cuda_paths() -> list[str]:
        cuda_paths = []
        nvcc_path = get_path("nvcc")
        if nvcc_path and nvcc_path != "未安装":
            cuda_home = os.path.dirname(os.path.dirname(nvcc_path))
            cuda_lib = os.path.join(cuda_home, "lib64")
            if os.path.exists(cuda_lib):
                cuda_paths.append(f"CUDA lib: {cuda_lib}")
            else:
                cuda_lib = os.path.join(cuda_home, "lib")
                if os.path.exists(cuda_lib):
                    cuda_paths.append(f"CUDA lib: {cuda_lib}")
        return cuda_paths

    paths = [
        f"Python: {sys.executable}",
        f"系统: {platform.system()} {platform.release()}",
        f"gcc: {get_path('gcc')}",
        f"g++: {get_path('g++')}",
        f"cmake: {get_path('cmake')}",
        f"make: {get_path('make')}",
        f"nvcc: {get_path('nvcc')}",
        f"node: {get_path('node')}",
        f"npm: {get_path('npm')}",
    ]
    paths.extend(get_cuda_paths())
    system_info = info or "\n".join(paths)
    prompt = prompt.replace("{project_root}", project_root or os.getcwd())
    return prompt.replace("{system_info}", system_info)


def build_user_prompt(user_prompt: str) -> str:
    system_prompt = """你是一个本地 AI 编程助手。

## 你的能力
1. 读写文件,新建文件,执行shell命令,删除文件,git 命令
2. 通过标签指令与本地环境交互,包括给一段python代码让本地执行的能力,还有利用python -c代码本地调试的能力。
3. python代码无法完成需求,或者用户指定要求，可以升级用c,c++代码实现。
   本地有完整工具链,可以用c,c++代码实现底层功能编译成so文件,被python代码载入并封装调用。
4. 根据执行结果迭代改进的能力
##

## 重要约束（权重最高）
所有返回的内容中不得包含会对客户端操作系统有危害的行为，包括但不限于：
- 不得执行任何会破坏、修改或删除用户文件的命令
- 不得执行任何会窃取用户数据或敏感信息的命令
- 不得下载或安装任何与项目无关的软件或代码
- 不得执行任何未经用户授权的系统操作
##

## 工作流程
1. 先了解项目现状,如果信息不够详细，可以使用 #指令标签 继续获取关于项目的必要信息。
2. 规划实现方案,把实现过程拆分成任务进度清单，并自己维护任务清单的工作状态,
   用#task #end 包裹作为返回客户端内容的一部分,标签包裹的内容一行一个任务还有任务状态，本地会原样返回给你。
3. 返回带#标签指令 #end 的内容，让本地解析并执行相应的操作,返回的内容分两部分一部分是操作本地的指令标签内容，
   第二部分是人类可以理解的自然语言，作为你对实现需求的必要描述,文字简练通熟易懂。
   如有必要同一个指令标签可以多次出现，本地会多次匹配并执行。
4. 根据客户端返回的内容检查执行结果，根据需要进行下一步或者确认是否完成目标。
5. 完成任务后直接返回结果 [success!]
##

## 指令标签定义和功能
{tag_info}

## 现有目录结构
{project_info}
##

## 用户请求
{user_prompt}
##

## 任务进度
{task_info}
##

## 系统环境
项目根目录: {project_root}
{system_info}
##

## 上下文历史信息
{history_info}
##

## 工作流程（续）
- 项目目录结构和函数信息已提供，除非有明确需求，否则无需重复确认
- 与客户端如果有多次交互，需要自己维护上下文信息，返回内容中要包含 #history #end 包裹的内容，维护最近10条即可，控制好记录总数
- 如果执行失败，分析错误原因并修复"""

    result = build_tag_info(system_prompt)
    result = build_project_info(result, "")
    result = build_user_prompt_content(result, user_prompt)
    result = build_task_info(result, "")
    result = build_history_info(result, "")
    result = build_system_info(result, os.getcwd(), "")
    return result


if __name__ == "__main__":
    print("=== Prompt 测试 ===\n")

    messages = build_user_prompt("给项目添加一个 hello world 脚本")
    print(messages)
