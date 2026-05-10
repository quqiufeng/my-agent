#!/usr/bin/env python3
"""
AutoBot 执行引擎测试用例
只测试白名单中的命令
"""
import sys
sys.path.insert(0, SCRIPT_DIR)

from executor import Executor

executor = Executor()

def test(name, command, expected_success=None, expected_contains=None):
    """执行单个测试用例"""
    print(f"\n{'='*60}")
    print(f"测试: {name}")
    print(f"命令: {command}")
    print(f"{'='*60}")
    
    result = executor.execute(command)
    
    print(f"成功: {result.get('success')}")
    print(f"返回码: {result.get('returncode')}")
    stdout = result.get('stdout', '')
    stderr = result.get('stderr', '')
    print(f"stdout: {stdout[:200]}")
    if stderr:
        print(f"stderr: {stderr[:200]}")
    
    if expected_success is not None:
        assert result.get('success') == expected_success, f"期望成功={expected_success}, 实际={result.get('success')}"
    
    if expected_contains:
        assert expected_contains in stdout or expected_contains in stderr, f"期望包含 '{expected_contains}'"
    
    print("✅ 通过")
    return result


# ===== 基础 Shell 命令测试 =====

print("\n" + "="*60)
print("基础 Shell 命令测试")
print("="*60)

test("pwd - 查看当前目录", "pwd", expected_success=True)
test("ls - 列出文件", "ls", expected_success=True)
test("ls -la - 详细信息", "ls -la", expected_success=True)
test("echo - 打印", "echo hello", expected_success=True)
test("date - 当前时间", "date", expected_success=True)
test("mkdir - 创建目录", "mkdir -p /tmp/autobot_test", expected_success=True)
test("touch - 创建文件", "touch /tmp/autobot_test/file.txt", expected_success=True)


# ===== Git 命令测试 =====

print("\n" + "="*60)
print("Git 命令测试")
print("="*60)

test("git status", "git status", expected_success=True)
test("git log --oneline -3", "git log --oneline -3", expected_success=True)
test("git branch", "git branch", expected_success=True)


# ===== Python 测试 =====

print("\n" + "="*60)
print("Python 测试")
print("="*60)

test("python3 --version", "python3 --version", expected_success=True)
test("python3 -c print", 'python3 -c "print(1+2)"', expected_success=True, expected_contains="3")


# ===== 管道和组合命令测试 =====

print("\n" + "="*60)
print("管道和组合命令测试")
print("="*60)

test("echo | grep", "echo hello_world | grep world", expected_success=True, expected_contains="world")
test("ls | grep", "ls | grep README", expected_success=True, expected_contains="README")
test("cd + ls", "cd /tmp && ls", expected_success=True)


# ===== 文件读写测试 =====

print("\n" + "="*60)
print("文件读写测试")
print("="*60)

test("echo > file", "echo test_content > /tmp/autobot_test/test.txt", expected_success=True)
test("cat file", "cat /tmp/autobot_test/test.txt", expected_success=True, expected_contains="test_content")


# ===== 危险命令测试 =====

print("\n" + "="*60)
print("危险命令测试 (应该被拦截)")
print("="*60)

test("rm -rf / (应该失败)", "rm -rf /", expected_success=False)
test("rm -rf .git (应该失败)", "rm -rf .git", expected_success=False)


# ===== 总结 =====

print("\n" + "="*60)
print("✅ 所有测试完成!")
print("="*60)
