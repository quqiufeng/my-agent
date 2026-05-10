#!/usr/bin/env python3
"""
AutoBot AI 模块测试用例
"""
import sys
sys.path.insert(0, SCRIPT_DIR)

from ai import AI

ai = AI()

def test(name, prompt, expected_contains=None):
    """执行单个测试"""
    print(f"\n{'='*60}")
    print(f"测试: {name}")
    print(f"输入: {prompt}")
    print(f"{'='*60}")
    
    result = ai.analyze(prompt)
    
    print(f"plan: {result.get('plan', [])[:2]}")
    print(f"summary: {result.get('summary', '')[:100]}")
    
    if expected_contains:
        plan_str = str(result.get('plan', []))
        if expected_contains not in plan_str:
            print(f"⚠️ 期望包含: {expected_contains}")
    
    print("✅ 完成")
    return result


# ===== Shell 命令识别测试 =====

print("\n" + "="*60)
print("Shell 命令识别测试")
print("="*60)

test("识别 pwd", "#shell\npwd\n#end", expected_contains="pwd")
test("识别 git status", "执行 git status")
test("识别 git log", "查看最近3次提交")
test("识别 ls -la", "列出当前目录详情")
test("识别 mkdir", "创建 test 目录")


# ===== Python 代码识别测试 =====

print("\n" + "="*60)
print("Python 代码识别测试")
print("="*60)

test("识别 python", "#code\nprint('hello')\n#end")
test("识别 import", "用 python 导入 json 模块")


# ===== 纯文本回复测试 =====

print("\n" + "="*60)
print("纯文本回复测试")
print("="*60)

test("问候", "你好")
test("自我介绍", "你是谁")
test("帮助", "帮助")


# ===== 复杂任务测试 =====

print("\n" + "="*60)
print("复杂任务测试")
print("="*60)

test("多步骤任务", "查看项目状态并列出 README.md 文件")
test("git + ls", "查看 git 状态和文件列表")


# ===== 总结 =====

print("\n" + "="*60)
print("✅ AI 测试完成!")
print("="*60)
