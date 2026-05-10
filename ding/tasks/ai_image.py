"""
AI 任务 - 处理文字消息 (AI对话 + 可生成图片)
"""
import sys
import os
import re
import json
import time
import hashlib
import requests

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult
from ai import AI
from executor import Executor
from dingtalk import DingTalk
from logger import task_logger as logger

SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class AIImageTask(BaseTask):
    """AI 文字任务 - 对话 + 生成图片"""
    task_type = "ai_image"
    
    def __init__(self):
        self.ai = AI()
        self.executor = Executor()
        self.dingtalk = DingTalk()
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        user_input = content.get("user_input", "")
        download_code = content.get("download_code", "")
        robot_code = content.get("robot_code", "")
        
        if download_code and robot_code:
            return self._handle_image(download_code, robot_code, content)
        
        if user_input:
            return self._handle_text(user_input, session_webhook)
        
        return TaskResult.err("未提供输入").to_dict()
    
    def _handle_image(self, download_code, robot_code, content):
        """处理图片消息"""
        prompt = content.get("prompt", "描述这张图片的内容")
        
        try:
            dt = dingtalk.get_dingtalk()
            image_url = dt.download_file(download_code, robot_code)
        except Exception as e:
            logger.error(f"图片下载失败: {e}")
            return TaskResult.err("图片下载失败").to_dict()
        
        if image_url:
            ai_result = self.ai.analyze_image(image_url, prompt)
            return TaskResult(
                success=True,
                stdout=ai_result.get("summary", "")
            ).to_dict()
        else:
            return TaskResult.err("图片下载失败").to_dict()
    
    def _handle_text(self, user_input, session_webhook):
        """处理文字消息 - AI 对话 + 可生成图片"""
        ai_result = self.ai.analyze(user_input)
        
        summary = ai_result.get("summary", "")
        
        # 检查 AI 是否返回了 #img 指令（本地图片生成）
        img_match = re.search(r'#img\s+(.+?)(?:\n|$)', summary, re.DOTALL)
        if img_match:
            logger.info(f"检测到 #img 指令: {img_match.group(1)[:100]}")
            img_prompt = img_match.group(1).strip()
            
            # 从原始输入中提取尺寸，附加到 prompt（AI 可能忽略了尺寸）
            size_from_input = self._extract_size_from_input(user_input)
            if size_from_input:
                img_prompt = f"{img_prompt} {size_from_input}"
                logger.info(f"附加用户指定尺寸: {size_from_input}")
            
            # 调用本地 ImgTask 生成图片
            from tasks.img import ImgTask
            img_task = ImgTask()
            img_result = img_task.execute({"raw": f"#img {img_prompt}"}, session_webhook)
            
            exec_responses = img_result.get("exec_responses", "")
            return TaskResult(
                success=img_result.get("success", False),
                stdout=img_result.get("stdout", ""),
                exec_responses=exec_responses
            ).to_dict()
        
        prompt_match = re.search(r'sf\.generate_image\("([^"]+)"\)', summary)
        if prompt_match:
            logger.info(f"图片提示词: {prompt_match.group(1)}")
        
        plan = ai_result.get("plan", [])
        
        if not plan and summary:
            summary_code_match = re.search(r'#code\s*(.*?)\s*#end', summary, re.DOTALL)
            if summary_code_match:
                plan = [summary]
        
        result = TaskResult(
            success=True,
            stdout=json.dumps(ai_result, ensure_ascii=False, indent=2),
            has_command=len(plan) > 0 or bool(summary)
        ).to_dict()
        
        if plan:
            exec_responses, has_cmd = self._execute_plan_steps(plan, session_webhook)
            result["exec_responses"] = exec_responses
            result["has_command"] = result.get("has_command", False) or has_cmd
        
        return result
    
    def _execute_plan_steps(self, plan, session_webhook):
        """执行计划步骤"""
        responses = []
        has_command = False
        
        for step in plan[:5]:
            step = step.strip()
            if not step:
                continue
            
            # 先检查 #write (写入文件)
            write_match = re.search(r'#write\s*(.*?)\s*#end', step, re.DOTALL | re.IGNORECASE)
            if write_match:
                content = write_match.group(1).strip()
                path_match = re.search(r'文件路径[：:](.+?)(?:\n|$)', content)
                if path_match:
                    file_path = path_match.group(1).strip()
                    code_match = re.search(r'文件内容[：:]\s*\n?(.*)', content, re.DOTALL)
                    file_content = code_match.group(1).strip() if code_match else ""
                    
                    try:
                        os.makedirs(os.path.dirname(file_path), exist_ok=True)
                        with open(file_path, 'w', encoding='utf-8') as f:
                            f.write(file_content)
                        responses.append(f"✅ 已写入文件: {file_path}")
                        has_command = True
                        
                        try:
                            from tasks import load_all_tasks
                            load_all_tasks()
                            responses.append(f"🔄 已重新加载任务")
                        except Exception as e:
                            logger.error(f"重新加载任务失败: {e}")
                    except Exception as e:
                        responses.append(f"❌ 写入失败: {e}")
                continue
            
            # 检查 #shell
            shell_match = re.search(r'#shell\s*(.*?)\s*#end', step, re.DOTALL)
            if shell_match:
                cmd = shell_match.group(1).strip()
                exec_result = self.executor.execute(cmd)
                responses.append(f"$ {cmd}\n{exec_result.get('stdout', '')[:300]}")
                has_command = True
                continue
            
            # 检查 #code
            code_match = re.search(r'#code\s*(.*?)\s*#end', step, re.DOTALL)
            if code_match:
                code = code_match.group(1).strip()
                
                # 注入 SCRIPT_DIR
                code = f"import os\nSCRIPT_DIR = '{SCRIPT_DIR}'\nimport sys\nsys.path.insert(0, SCRIPT_DIR)\n" + code
                
                exec_result = self.executor.execute_python_subprocess(code)
                stdout = exec_result.get('stdout', '')
                stderr = exec_result.get('stderr', '')
                
                # 添加执行结果提示
                if stdout:
                    responses.append(f"📥 代码执行结果:\n")
                if stderr:
                    responses.append(f"❌ 错误:\n{stderr[:300]}")
                
                promt  = '''
                【十一、图片生成流程】
                ================================================================================
                 【重要规则 - 如何判断用户发送内容是生成图片的需求】
                 如果用户发送的消息是在描述一张图片的内容，
                 或者用户希望你根据描述生成一张图片或者是直接的生成图片需求
                 请直接返回#code #end 包裹的图片生成代码，
                 将用户发送的内容优化成可以用于大模型生成高质量图片且细节丰富的提示词，做为提示词参数$prompt

                 【返回给用户的内容格式】 用#code #end 包裹起来的内容 
                 $prompt参数 就是你将用户发送的消息 处理并优化过的用于生成图片的提示词

                 #code
                 import siliconflow
                 sf = siliconflow.SiliconFlow() 
                 result = sf.generate_image($prompt)       
                 print(result["image_url"])
                 #end

                 【系统自动执行 #code #end 包裹起来的代码】
                 1. 执行代码 → 提取 result["image_url"]
                 2. 下载图片 → 上传钉钉获取 media_id
                 3. 发送图片给用户

                 【重要】不要创建新插件！只返回 #code 格式的执行代码
                 【返回格式不能改】{"success": True, "image_url": "...", "local_path": "..."}
                # ============================================================
                '''
                # 提取图片 URL
                url_match = re.search(r'https?://[^\s]+', stdout, re.I)
                if url_match:
                    responses.append(f"📷 图片: {url_match.group(0)}")
                    
                    # 自动下载上传
                    try:
                        img_resp = requests.get(url_match.group(0), timeout=60)
                        if img_resp.status_code == 200:
                            timestamp = str(int(time.time() * 1000))
                            random_str = hashlib.md5(timestamp.encode()).hexdigest()[:12]
                            local_path = os.path.join(SCRIPT_DIR, f"image_{random_str}.png")
                            with open(local_path, "wb") as f:
                                f.write(img_resp.content)
                            responses.append(f"__LOCAL_IMAGE__: {local_path}")
                            
                            # 上传到钉钉
                            media_id = self.dingtalk.upload_media("image", file_content=img_resp.content, filename="image.png")
                            if media_id:
                                responses.append(f"__MEDIA_ID__: {media_id}")
                                # 发送 markdown 消息
                                self.dingtalk.send_markdown_image(session_webhook, media_id)
                    except Exception as e:
                        logger.error(f"图片下载/上传失败: {e}")
                    
                    has_command = True
                elif stdout.strip():
                    responses.append(stdout[:400])
        
        return "\n\n".join(responses), has_command
    
    def _extract_size_from_input(self, user_input: str) -> str:
        """从用户原始输入中提取尺寸参数"""
        # 匹配 120x120, 512x512 等格式
        size_match = re.search(r'(\d{2,4})\s*[xX×]\s*(\d{2,4})', user_input)
        if size_match:
            w, h = size_match.group(1), size_match.group(2)
            if 16 <= int(w) <= 2048 and 16 <= int(h) <= 2048:
                return f"{w} {h}"
        
        # 匹配末尾两个数字（如 "50 50"）
        parts = user_input.split()
        if len(parts) >= 3:
            if parts[-1].isdigit() and parts[-2].isdigit():
                w, h = parts[-2], parts[-1]
                if 16 <= int(w) <= 2048 and 16 <= int(h) <= 2048:
                    return f"{w} {h}"
        
        return ""
