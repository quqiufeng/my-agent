import subprocess
import shlex
import re
import os
import sys
import io
import json
import base64
import time
import datetime
import random
import uuid
import hashlib
import hmac

from config import Config
from logger import executor_logger as logger


class Executor:
    """执行模块：安全地执行命令 + Python 沙盒"""

    def __init__(
        self, forbidden_patterns=None, work_dir=None, timeout=None, sandbox_dir=None
    ):
        self.forbidden = forbidden_patterns or Config.FORBIDDEN_PATTERNS
        self.work_dir = work_dir or Config.WORK_DIR
        self.timeout = timeout or Config.TIMEOUT
        self.sandbox_dir = sandbox_dir or Config.SANDBOX_DIR  # 沙盒安全目录
        # 沙盒白名单 - 允许的 Python 模块
        self.allowed_modules = {
            # 标准库
            "json",
            "re",
            "os",
            "sys",
            "time",
            "datetime",
            "random",
            "uuid",
            "hashlib",
            "hmac",
            "base64",
            "urllib",
            "http",
            "ssl",
            "socket",
            "pathlib",
            "subprocess",
            "io",
            "tempfile",
            "struct",
            "math",
            # 第三方库
            "requests",
            "openai",
            "pillow",
            "numpy",
            "pandas",
            # 本地模块
        }

    def execute(self, command, cwd=None, use_proxy=False):
        """执行 shell 命令，返回结果"""
        # 安全检查
        if not self.check_safety(command):
            return {
                "success": False,
                "error": "命令安全检查未通过",
                "stdout": "",
                "stderr": "禁止执行危险命令",
            }

        # 确定工作目录
        if cwd is None:
            cwd = self.work_dir

        # 获取代理环境变量
        env = os.environ.copy()
        if use_proxy or (not use_proxy and Config.HTTP_PROXY):
            if Config.HTTP_PROXY:
                env["http_proxy"] = Config.HTTP_PROXY
                env["HTTP_PROXY"] = Config.HTTP_PROXY
            if Config.HTTPS_PROXY:
                env["https_proxy"] = Config.HTTPS_PROXY
                env["HTTPS_PROXY"] = Config.HTTPS_PROXY

        # 执行命令
        try:
            # 安全执行：将命令字符串拆分为列表，避免 shell 注入
            cmd_list = shlex.split(command) if isinstance(command, str) else command
            result = subprocess.run(
                cmd_list,
                shell=False,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=self.timeout,
                env=env,
            )

            return {
                "success": result.returncode == 0,
                "returncode": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "command": command,
            }

        except subprocess.TimeoutExpired:
            # 超时了，如果没开代理则重试
            if not use_proxy and (Config.HTTP_PROXY or Config.HTTPS_PROXY):
                logger.warning(f"命令超时，尝试代理... (command: {command[:50]})")
                return self.execute(command, cwd, use_proxy=True)
            return {
                "success": False,
                "error": "命令执行超时",
                "stdout": "",
                "stderr": f"超时 {self.timeout} 秒",
            }
        except Exception as e:
            # 如果是网络错误，且没开代理，则重试
            if not use_proxy and (Config.HTTP_PROXY or Config.HTTPS_PROXY):
                if "Connection" in str(e) or "network" in str(e).lower():
                    logger.warning(f"网络错误: {e}，尝试代理...")
                    return self.execute(command, cwd, use_proxy=True)
            return {"success": False, "error": str(e), "stdout": "", "stderr": str(e)}

    def execute_python(self, code, api_key=None, model=None):
        """执行 Python 代码（沙盒模式）"""

        # 预处理代码：注入 API key
        if api_key:
            code = code.replace("YOUR_API_KEY", api_key)
            code = code.replace('"YOUR_KEY"', f'"{api_key}"')
            code = code.replace("'YOUR_KEY'", f"'{api_key}'")

        if model:
            code = code.replace("YOUR_MODEL", model)

        # 创建受限的执行环境
        sandbox_globals = {
            "__builtins__": {
                "__import__": self._safe_import,
                "print": print,
                "len": len,
                "str": str,
                "int": int,
                "float": float,
                "bool": bool,
                "list": list,
                "dict": dict,
                "tuple": tuple,
                "set": set,
                "range": range,
                "enumerate": enumerate,
                "zip": zip,
                "map": map,
                "filter": filter,
                "sorted": sorted,
                "sum": sum,
                "min": min,
                "max": max,
                "abs": abs,
                "round": round,
                "open": self._safe_open,
                "json": json,
                "base64": base64,
            },
            "os": os,
            "sys": sys,
            "time": time,
            "datetime": datetime,
            "random": random,
            "uuid": uuid,
            "hashlib": hashlib,
            "hmac": hmac,
            "io": io,
        }

        # 捕获输出
        stdout_capture = io.StringIO()
        stderr_capture = io.StringIO()

        old_stdout = sys.stdout
        old_stderr = sys.stderr

        try:
            sys.stdout = stdout_capture
            sys.stderr = stderr_capture

            exec(code, sandbox_globals)

            stdout = stdout_capture.getvalue()
            stderr = stderr_capture.getvalue()

            return {
                "success": True,
                "stdout": stdout,
                "stderr": stderr,
                "type": "python",
            }

        except Exception as e:
            return {
                "success": False,
                "stdout": stdout_capture.getvalue(),
                "stderr": f"{type(e).__name__}: {str(e)}",
                "error": str(e),
                "type": "python",
            }

        finally:
            sys.stdout = old_stdout
            sys.stderr = old_stderr

    def execute_python_subprocess(self, code, api_key=None, model=None):
        """通过 subprocess 执行 Python 代码（更安全）"""

        # 预处理代码
        if api_key:
            code = code.replace("YOUR_API_KEY", api_key)
            code = code.replace('"YOUR_KEY"', f'"{api_key}"')
            code = code.replace("'YOUR_KEY'", f"'{api_key}'")

        # 如果代码中有空的 api_key 或 None，填充实际 key
        if Config.API_KEY:
            code = code.replace('api_key=""', f'api_key="{Config.API_KEY}"')
            code = code.replace('api_key = ""', f'api_key = "{Config.API_KEY}"')
            code = code.replace("api_key=None", f'api_key="{Config.API_KEY}"')
            code = code.replace("api_key = None", f'api_key="{Config.API_KEY}"')

        # 替换 YOUR_API_KEY
        if Config.API_KEY:
            code = code.replace("YOUR_API_KEY", Config.API_KEY)

        # 如果调用 SiliconFlow API，添加 base_url
        if "api.siliconflow.cn" not in code and "siliconflow" in code.lower():
            # 检查是否需要添加 base_url
            if "base_url" not in code and "OpenAI" in code:
                code = code.replace(
                    "OpenAI(", 'OpenAI(base_url="https://api.siliconflow.cn/v1", '
                )

        if model:
            code = code.replace("YOUR_MODEL", model)

        # 添加沙盒限制代码
        sandbox_code = self._wrap_sandbox_code(code)

        # 写入临时文件
        import tempfile

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".py", delete=False, encoding="utf-8"
        ) as f:
            f.write(sandbox_code)
            temp_file = f.name

        try:
            result = subprocess.run(
                ["python3", temp_file],
                capture_output=True,
                text=True,
                timeout=self.timeout,
                cwd=self.sandbox_dir,  # 限制工作目录
            )

            return {
                "success": result.returncode == 0,
                "returncode": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "type": "python",
            }

        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "error": "Python 代码执行超时",
                "stdout": "",
                "stderr": f"超时 {self.timeout} 秒",
                "type": "python",
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "stdout": "",
                "stderr": str(e),
                "type": "python",
            }
        finally:
            # 清理临时文件
            try:
                os.unlink(temp_file)
            except Exception:
                pass

    def _wrap_sandbox_code(self, code):
        """包装代码，添加沙盒限制"""
        sandbox_dir = os.path.abspath(self.sandbox_dir)

        wrapper = f'''# -*- coding: utf-8 -*-
"""
AutoBot Python Sandbox
限制所有文件操作只能在这个目录: {sandbox_dir}
"""

import os
import sys
import shutil

# SCRIPT_DIR 定义
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else "{sandbox_dir}"

# 添加脚本目录到 Python 路径
sys.path.insert(0, SCRIPT_DIR)

# 沙盒安全目录
SANDBOX_DIR = "{sandbox_dir}"

def _check_path(path):
    """检查路径是否在沙盒目录内"""
    if path is None:
        return True
    
    # 获取绝对路径
    try:
        abs_path = os.path.abspath(path)
    except Exception:
        return False
    
    # 检查是否在沙盒目录内
    if not abs_path.startswith(SANDBOX_DIR):
        raise PermissionError(f"禁止访问沙盒外目录: {{path}} (只允许: {{SANDBOX_DIR}})")
    return True

# 安全的 open 函数
_original_open = open

def _safe_open(path, mode='r', *args, **kwargs):
    _check_path(path)
    # 限制写入模式
    if 'w' in mode or 'a' in mode or 'x' in mode:
        # 检查父目录是否存在
        parent = os.path.dirname(os.path.abspath(path))
        if not os.path.exists(parent):
            raise FileNotFoundError(f"目录不存在: {{parent}}")
    return _original_open(path, mode, *args, **kwargs)

# 替换内置 open
exec("open = _safe_open")

# 禁用危险操作
_original_rmtree = shutil.rmtree

def _no_rmtree(*args, **kwargs):
    raise PermissionError("禁止使用 rmtree，危险操作")

shutil.rmtree = _no_rmtree

# 运行用户代码
{code}
'''
        return wrapper

    def _safe_import(self, name, *args, **kwargs):
        """安全导入模块"""
        # 检查是否在白名单中
        module_name = name.split(".")[0]
        if module_name in self.allowed_modules:
            return __import__(name, *args, **kwargs)
        raise ImportError(f"不允许导入模块: {name}")

    def _safe_open(self, path, mode="r", *args, **kwargs):
        """安全的文件操作"""
        # 限制只能操作工作目录
        if "w" in mode or "a" in mode:
            # 写入操作只能在工作目录
            if not os.path.abspath(path).startswith(os.path.abspath(self.work_dir)):
                raise PermissionError(f"不允许写入目录外: {path}")
        return open(path, mode, *args, **kwargs)

    def check_safety(self, command):
        """安全检查 - 黑名单模式：只检查禁止模式，其他都允许"""

        cmd = command.strip()

        if not cmd:
            return False

        # 检查禁止的模式
        for pattern in self.forbidden:
            try:
                if re.search(pattern, cmd, re.IGNORECASE):
                    logger.error(f"命令包含禁止模式: {pattern}")
                    return False
            except re.error:
                if pattern.lower() in cmd.lower():
                    logger.error(f"命令包含禁止模式: {pattern}")
                    return False

        return True

    def execute_steps(self, steps):
        """执行多步命令，返回每步结果"""
        results = []

        for i, step in enumerate(steps):
            logger.info(f"执行步骤 {i + 1}/{len(steps)}: {step}")
            result = self.execute(step)
            results.append(result)

            if not result["success"]:
                logger.error(
                    f"步骤失败: {result.get('stderr', result.get('error', '未知错误'))}"
                )
                break
            else:
                # 打印成功结果（截断过长输出）
                stdout = result.get("stdout", "")
                if stdout:
                    preview = stdout[:500] + "..." if len(stdout) > 500 else stdout
                    logger.debug(f"输出: {preview}")

        return results

    def get_git_status(self):
        """获取 Git 状态"""
        result = self.execute("git status")
        return result

    def get_git_diff(self, file_path=None):
        """获取 Git diff"""
        if file_path:
            cmd = f"git diff {file_path}"
        else:
            cmd = "git diff"
        result = self.execute(cmd)
        return result

    def git_add(self, files):
        """git add 文件"""
        if isinstance(files, list):
            files = " ".join(files)
        cmd = f"git add {files}"
        return self.execute(cmd)

    def git_commit(self, message):
        """git commit"""
        cmd = f'git commit -m "{message}"'
        return self.execute(cmd)

    def git_push(self):
        """git push"""
        return self.execute("git push")

    def git_commit_and_push(self, message):
        """git add + commit + push"""
        # git add .
        result = self.execute("git add .")
        if not result["success"]:
            return result

        # git commit
        result = self.git_commit(message)
        if not result["success"]:
            return result

        # git push
        return self.git_push()

    def run_lua(self, script_path):
        """运行 Lua 脚本"""
        # 优先使用配置的 luajit
        cmd = f"luajit {script_path}"
        return self.execute(cmd)

    def run_npm(self, command, project_path=None):
        """运行 npm 命令"""
        cmd = f"npm {command}"
        return self.execute(cmd, cwd=project_path)

    def run_make(self, target=None):
        """运行 make"""
        if target:
            cmd = f"make {target}"
        else:
            cmd = "make"
        return self.execute(cmd)

    def execute_auto(self, code_or_cmd, api_key=None, model=None):
        """自动检测并执行：Python 代码 或 Shell 命令 或 下载"""

        # 提取 #shell, #code, #download 包裹的内容
        extracted = self._extract_commands(code_or_cmd)

        if extracted["type"] == "python":
            logger.info("检测到 Python 代码，执行沙盒...")
            return self.execute_python_subprocess(extracted["code"], api_key, model)
        elif extracted["type"] == "shell":
            logger.info("检测到 Shell 命令，执行...")
            return self.execute(extracted["code"])
        elif extracted["type"] == "download":
            logger.info("检测到下载链接，执行下载...")
            return self.download_file(extracted["code"])
        else:
            # 尝试自动检测
            is_python = self._is_python_code(code_or_cmd)

            if is_python:
                logger.info("默认为 Python 代码，执行沙盒...")
                return self.execute_python_subprocess(code_or_cmd, api_key, model)
            else:
                logger.info("默认为 Shell 命令，执行...")
                return self.execute(code_or_cmd)

    def _extract_commands(self, text):
        """从文本中提取 #shell 或 #code 或 #download 包裹的内容"""

        # 提取 #download ... #end
        download_match = re.search(
            r"#download\s*(.*?)\s*#end", text, re.DOTALL | re.IGNORECASE
        )
        if download_match:
            url = download_match.group(1).strip()
            return {"type": "download", "code": url}

        # 提取 #code ... #end
        code_match = re.search(r"#code\s*(.*?)\s*#end", text, re.DOTALL | re.IGNORECASE)
        if code_match:
            return {"type": "python", "code": code_match.group(1).strip()}

        # 提取 #shell ... #end
        shell_match = re.search(
            r"#shell\s*(.*?)\s*#end", text, re.DOTALL | re.IGNORECASE
        )
        if shell_match:
            return {"type": "shell", "code": shell_match.group(1).strip()}

        # 没有找到标记
        return {"type": "unknown", "code": text.strip()}

    def download_file(self, url, filename=None):
        """下载文件到本地"""
        import urllib.parse

        # 从 URL 提取文件名
        if not filename:
            parsed = urllib.parse.urlparse(url)
            filename = os.path.basename(parsed.path)
            if not filename:
                filename = "download_file"

        # wget 下载
        cmd = f'wget -O "{filename}" "{url}"'
        return self.execute(cmd)

    def _is_python_code(self, code):
        """检测是否是 Python 代码"""
        # Python 代码特征
        python_indicators = [
            "import ",
            "from ",
            "def ",
            "class ",
            "print(",
            "if __name__",
            "    ",  # 缩进
            "print (",
            "=",  # 赋值
            "(",  # 函数调用
        ]

        # 统计特征
        score = 0
        for indicator in python_indicators:
            if indicator in code:
                score += 1

        # 如果有 2 个以上特征，认为是 Python
        return score >= 2


# 测试
if __name__ == "__main__":
    e = Executor()

    # 测试安全检查
    print("=== 安全检查测试 ===")
    print(f"git status: {e.check_safety('git status')}")
    print(f"ls -la: {e.check_safety('ls -la')}")
    print(f"rm -rf /: {e.check_safety('rm -rf /')}")
    print(f"sudo shutdown: {e.check_safety('sudo shutdown')}")

    # 测试执行
    print("\n=== 执行测试 ===")
    result = e.execute("ls -la")
    print(f"ls -la: {result['success']}")
