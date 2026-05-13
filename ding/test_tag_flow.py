#!/usr/bin/env python3
"""
验证 #标签 解析执行流程
"""
import os
import sys
import re
import json

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from executor import Executor

# ========== 1. 测试标签解析 ==========
print("=" * 60)
print("测试 1: 标签正则解析")
print("=" * 60)

test_messages = [
    ("#shell ls -la", "shell"),
    ("#code print('hello')", "code"),

    ("普通文字消息", "ai_image"),
    ("#kimi 你好", "kimi"),
    ("#agent master 写个排序", "agent"),
]

for msg, expected in test_messages:
    # 模拟 autobot_dingtalk.py 的匹配逻辑
    directive_match = re.match(r'#(\w+)', msg)
    if directive_match:
        directive_name = directive_match.group(1)
        print(f"✓ '{msg}' → 匹配指令: #{directive_name}")
    else:
        print(f"✓ '{msg}' → 无指令, 默认转发到 ai_image")

print()

# ========== 2. 测试任务分发 ==========
print("=" * 60)
print("测试 2: 任务分发到注册表")
print("=" * 60)

from tasks import load_all_tasks, get_task, list_tasks

load_all_tasks()
print(f"已加载任务: {list_tasks()}")

# 模拟各种任务类型
test_tasks = [
    {"type": "shell", "content": {"raw": "#shell echo hello"}},
    {"type": "code", "content": {"raw": "#code print(1+1)"}},

    {"type": "test", "content": {"raw": "#test"}},
]

for task in test_tasks:
    task_type = task.get("type")
    handler = get_task(task_type)
    if handler:
        print(f"✓ 任务类型 '{task_type}' → 处理器: {type(handler).__name__}")
    else:
        print(f"✗ 任务类型 '{task_type}' → 无处理器")

print()

# ========== 3. 测试 AI 返回的标签执行 ==========
print("=" * 60)
print("测试 3: AI 返回结果中的 #标签 解析执行")
print("=" * 60)

# 模拟 AI 返回的包含标签的内容
ai_response = """
用户想要生成一张图片。

#code
import siliconflow
sf = siliconflow.SiliconFlow()
result = sf.generate_image("一只可爱的猫")
print(result["image_url"])
#end

任务完成！
"""

# 模拟 ai_image.py 中的标签提取
print("\n--- 提取 #code 标签 ---")
code_match = re.search(r'#code\s*(.*?)\s*#end', ai_response, re.DOTALL)
if code_match:
    code = code_match.group(1).strip()
    print(f"提取到的代码:\n{code}")
else:
    print("未找到 #code 标签")

# 测试 #shell 提取
shell_response = """
#shell
ls -la /tmp
#end
"""
print("\n--- 提取 #shell 标签 ---")
shell_match = re.search(r'#shell\s*(.*?)\s*#end', shell_response, re.DOTALL)
if shell_match:
    cmd = shell_match.group(1).strip()
    print(f"提取到的命令: {cmd}")
else:
    print("未找到 #shell 标签")

# 测试 #write 提取
write_response = """
#write
file:tasks/hello.py
content:
from tasks.base import BaseTask, TaskResult

class HelloTask(BaseTask):
    task_type = "hello"
    
    def execute(self, content, session_webhook=None):
        return TaskResult.ok("Hello!").to_dict()
#end
"""
print("\n--- 提取 #write 标签 ---")
write_match = re.search(r'#write\s*(.*?)\s*#end', write_response, re.DOTALL | re.IGNORECASE)
if write_match:
    content = write_match.group(1).strip()
    print(f"提取到的内容长度: {len(content)} chars")
    # 解析文件名
    path_match = re.search(r'文件路径[：:](.+?)(?:\n|$)', content)
    if path_match:
        file_path = path_match.group(1).strip()
        print(f"文件路径: {file_path}")
else:
    print("未找到 #write 标签")

print()

# ========== 4. 测试实际执行 ==========
print("=" * 60)
print("测试 4: 实际执行 #shell 和 #code")
print("=" * 60)

executor = Executor()

# 测试 #shell 执行
test_cmd = "echo 'Hello from shell'"
print(f"\n执行: {test_cmd}")
result = executor.execute(test_cmd)
print(f"结果: success={result['success']}, stdout={result['stdout'].strip()}")

# 测试 #code 执行
test_code = "print('Hello from python')"
print(f"\n执行代码:\n{test_code}")
result = executor.execute_python_subprocess(test_code)
print(f"结果: success={result['success']}, stdout={result['stdout'].strip()}")

print()

# ========== 5. 测试完整 IPC 流程 ==========
print("=" * 60)
print("测试 5: IPC 文件通信流程")
print("=" * 60)

TASK_DIR = "/tmp/autobot_tasks"
TASK_FILE = os.path.join(TASK_DIR, "task.json")
RESULT_FILE = os.path.join(TASK_DIR, "result.json")

# 清理
for f in [TASK_FILE, RESULT_FILE]:
    if os.path.exists(f):
        os.remove(f)

# 模拟主进程写入任务
task = {
    "id": "test-001",
    "type": "test",
    "content": {"raw": "#test"},
    "timestamp": 1234567890
}

os.makedirs(TASK_DIR, exist_ok=True)
with open(TASK_FILE, 'w') as f:
    json.dump(task, f, ensure_ascii=False)
print(f"✓ 主进程写入任务: {TASK_FILE}")

# 模拟 Worker 读取任务
if os.path.exists(TASK_FILE):
    with open(TASK_FILE, 'r') as f:
        received_task = json.load(f)
    print(f"✓ Worker 读取任务: type={received_task['type']}, id={received_task['id']}")
    
    # 模拟执行
    os.remove(TASK_FILE)
    print("✓ Worker 删除任务文件")
    
    # 写入结果
    result = {
        "task_id": received_task['id'],
        "type": received_task['type'],
        "success": True,
        "stdout": "测试成功",
        "stderr": "",
        "error": ""
    }
    with open(RESULT_FILE, 'w') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"✓ Worker 写入结果: {RESULT_FILE}")

# 模拟主进程读取结果
if os.path.exists(RESULT_FILE):
    with open(RESULT_FILE, 'r') as f:
        received_result = json.load(f)
    print(f"✓ 主进程读取结果: success={received_result['success']}, stdout={received_result['stdout']}")
    os.remove(RESULT_FILE)
    print("✓ 主进程删除结果文件")

print()
print("=" * 60)
print("所有测试完成!")
print("=" * 60)
