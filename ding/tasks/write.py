"""
Write 指令任务
将内容写入指定文件
"""
import sys
import os
import ast

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult


def format_python_code(code: str) -> str:
    """格式化 Python 代码"""
    try:
        tree = ast.parse(code)
        return ast.unparse(tree)
    except SyntaxError:
        return code
    except Exception:
        return code


def parse_write_args(raw: str) -> tuple:
    """解析 write 指令参数"""
    filename = ""
    file_content = ""
    
    if raw.startswith("file:"):
        content_idx = raw.find("content:")
        if content_idx != -1:
            filename = raw[5:content_idx].strip()
            file_content = raw[content_idx + 8:].strip()
        else:
            filename = raw[5:].strip()
            file_content = ""
    elif raw.startswith("filename:"):
        content_idx = raw.find("content:")
        if content_idx != -1:
            filename = raw[9:content_idx].strip()
            file_content = raw[content_idx + 8:].strip()
        else:
            filename = raw[9:].strip()
            file_content = ""
    else:
        parts = raw.split(" ", 1)
        filename = parts[0]
        file_content = parts[1] if len(parts) > 1 else ""
    
    # 将 \n 转换为真正的换行符
    file_content = file_content.replace('\\n', '\n')
    
    return filename, file_content


class WriteTask(BaseTask):
    """写入文件"""
    task_type = "write"
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        filename = content.get("filename", "")
        file_content = content.get("content", "")
        text = content.get("raw", "")
        
        text = text.replace("#write", "").strip()
        if not filename and "raw" in content:
            filename, file_content = parse_write_args(text)
        if not filename:
            return TaskResult.err("未提供文件名").to_dict()
        if not text:
            return TaskResult.err("用法: #write 文件名 内容\n或 #write file:文件名 content:内容").to_dict()
        
        # 获取脚本目录作为基础目录
        script_dir = os.path.dirname(os.path.abspath(__file__))
        base_dir = os.path.dirname(script_dir)
        file_path = os.path.join(base_dir, filename)
        
        # 检查文件是否已存在
        if os.path.exists(file_path):
            return TaskResult.err(f"文件已存在: {filename}").to_dict()
        
        try:
            # 先创建目录
            dir_path = os.path.dirname(file_path)
            if dir_path:
                os.makedirs(dir_path, exist_ok=True)
            
            # 格式化 Python 代码
            formatted_code = format_python_code(file_content)
            
            # 创建文件并写入内容
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(formatted_code)
            
            return TaskResult.ok(stdout=f"已写入文件: {file_path}").to_dict()
        except Exception as e:
            return TaskResult.err(f"写入文件失败: {e}").to_dict()
