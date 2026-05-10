#!/usr/bin/env python3
"""钉钉 WebSocket Stream 消息接收 - 任务分发架构

支持消息类型:
- text:      文本消息 (含 #指令)
- picture:   图片消息
- file:      文件消息
- voice:     语音消息
- markdown:  Markdown 消息
"""
import os
import sys
import logging
import json
import requests
import time
import uuid
import re

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

import dingtalk_stream
from dingtalk_stream import Credential, ChatbotHandler, AckMessage
from config import Config

LOG_FILE = os.path.join(SCRIPT_DIR, "run.log")
logger = logging.getLogger(__name__)
fh = logging.FileHandler(LOG_FILE)
fh.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
logger.addHandler(fh)
logger.setLevel(logging.DEBUG)

CLIENT_ID = Config.DINGTALK_CLIENT_ID
CLIENT_SECRET = Config.DINGTALK_CLIENT_SECRET


class AutoBotHandler(ChatbotHandler):
    def __init__(self, client=None):
        super().__init__()
        self.client = client
        self.task_dir = "/tmp/autobot_tasks"
        self.task_file = os.path.join(self.task_dir, "task.json")
        self.result_file = os.path.join(self.task_dir, "result.json")
        os.makedirs(self.task_dir, exist_ok=True)
    
    def dispatch_task(self, task_type, content, session_webhook=None, timeout=60):
        task_id = str(uuid.uuid4())
        task = {
            "id": task_id,
            "type": task_type,
            "content": content,
            "session_webhook": session_webhook,
            "timestamp": time.time()
        }
        
        if os.path.exists(self.result_file):
            os.remove(self.result_file)
        
        with open(self.task_file, 'w') as f:
            json.dump(task, f, ensure_ascii=False)
        
        start_time = time.time()
        while time.time() - start_time < timeout:
            if os.path.exists(self.result_file):
                with open(self.result_file, 'r') as f:
                    result = json.load(f)
                os.remove(self.result_file)
                return result
            time.sleep(0.5)
        
        return {
            "task_id": task_id,
            "type": task_type,
            "success": False,
            "error": f"超时 ({timeout}秒)",
            "stdout": ""
        }
    
    def _reply_text(self, text, msg):
        """回复文本消息（封装错误处理）"""
        try:
            self.reply_text(text[:1000], msg)
        except Exception as e:
            logger.error(f"回复消息失败: {e}")
    
    def _extract_text(self, msg, data):
        """从消息中提取文本内容（兼容多种消息类型）"""
        msg_type = data.get("msgtype", "")
        
        # 文本消息
        if msg_type == "text" and msg.text:
            return msg.text.content.strip()
        
        # Markdown 消息
        if msg_type == "markdown" and msg.markdown:
            return msg.markdown.text.strip()
        
        # 富文本消息
        if msg_type == "richText" and msg.rich_text:
            return msg.rich_text.content.strip()
        
        return ""
    
    async def process(self, callback):
        data = callback.data
        if not data:
            return AckMessage.STATUS_OK, 'OK'
        
        msg_type = data.get("msgtype")
        session_webhook = data.get("sessionWebhook")
        msg = dingtalk_stream.ChatbotMessage.from_dict(data)
        
        # ==================== 图片消息 ====================
        if msg_type == "picture":
            content = data.get("content", {})
            download_code = content.get("downloadCode")
            robot_code = data.get("robotCode")
            if download_code:
                result = self.dispatch_task("ai_analyze", {
                    "download_code": download_code,
                    "robot_code": robot_code,
                    "prompt": "描述这张图片"
                }, timeout=60)
                result_text = result.get('stdout', '图片已分析')
                if result_text and result_text != '图片已分析':
                    self._reply_text(result_text[:500], msg)
            return AckMessage.STATUS_OK, 'OK'
        
        # ==================== 文件消息 ====================
        if msg_type == "file":
            content = data.get("content", {})
            download_code = content.get("downloadCode")
            robot_code = data.get("robotCode")
            file_name = content.get("fileName", "未知文件")
            if download_code:
                self._reply_text(f"收到文件: {file_name}\n正在分析...", msg)
                result = self.dispatch_task("ai_analyze", {
                    "download_code": download_code,
                    "robot_code": robot_code,
                    "prompt": "分析这个文件的内容"
                }, timeout=120)
                result_text = result.get('stdout', '文件已分析')
                if result_text:
                    self._reply_text(result_text[:800], msg)
            return AckMessage.STATUS_OK, 'OK'
        
        # ==================== 语音消息 ====================
        if msg_type == "voice":
            content = data.get("content", {})
            download_code = content.get("downloadCode")
            robot_code = data.get("robotCode")
            if download_code:
                self._reply_text("收到语音消息，正在识别...", msg)
                result = self.dispatch_task("ai_analyze", {
                    "download_code": download_code,
                    "robot_code": robot_code,
                    "prompt": "转写这段语音内容"
                }, timeout=120)
                result_text = result.get('stdout', '语音已识别')
                if result_text:
                    self._reply_text(f"语音内容:\n{result_text[:500]}", msg)
            return AckMessage.STATUS_OK, 'OK'
        
        # ==================== 文本/Markdown 消息 ====================
        text = self._extract_text(msg, data)
        if not text:
            return AckMessage.STATUS_OK, 'OK'
        
        # 群聊中 @机器人 的消息处理（去掉 @机器人 前缀）
        # 钉钉群聊中 @机器人的消息格式: "@机器人 内容"
        at_users = data.get("atUsers", [])
        robot_code = data.get("robotCode", "")
        if at_users:
            # 去掉 @机器人 的文本
            for at_user in at_users:
                at_user_id = at_user.get("dingtalkId", "")
                if at_user_id:
                    text = re.sub(rf"@{re.escape(at_user_id)}\s*", "", text).strip()
        
        # 匹配 #指令 每个指令的实现代码在 task/指令.py
        directive_match = re.match(r'#(\w+)', text)
        if directive_match:
            directive_name = directive_match.group(1)
            task_file = os.path.join(os.path.dirname(__file__), "tasks", f"{directive_name}.py")
            if os.path.exists(task_file):
                self._reply_text("执行指令...", msg)
                result = self.dispatch_task(directive_name, {"raw": text}, session_webhook=session_webhook, timeout=120)
                
                # 检查 Worker 是否已发送图片（如 #img 指令）
                exec_responses = result.get('exec_responses', '')
                if exec_responses and '__MEDIA_ID__' in exec_responses:
                    # Worker 已发送图片，不再发送文本回复
                    return AckMessage.STATUS_OK, 'OK'
                
                # 否则回复文本结果
                output = result.get('stdout', '') or result.get('stderr', '') or result.get('error', '')
                self._reply_text(f"{output[:500]}", msg)
                return AckMessage.STATUS_OK, 'OK'
        
        # 默认文字消息 -> ai_image 任务 (AI 对话 + 可生成图片)
        task_result = self.dispatch_task(
            "ai_image",
            {"user_input": text},
            session_webhook=session_webhook,
            timeout=180
        )
        
        exec_responses = task_result.get('exec_responses', '')
        
        # 提取图片 URL
        image_url_match = re.search(r'📷 图片: (https?://\S+)', exec_responses) if exec_responses else None
        image_url = image_url_match.group(1) if image_url_match else None
        
        if exec_responses:
            clean_response = re.sub(r'📷 图片: https?://\S+', '', exec_responses)
            clean_response = re.sub(r'__MEDIA_ID__: \S+', '', clean_response)
            clean_response = re.sub(r'__LOCAL_IMAGE__: \S+', '', clean_response)
            response = clean_response.strip()
        else:
            response = ""
        
        # 如果 Worker 已发送图片消息，不再发送文本回复
        if exec_responses and '__MEDIA_ID__' in exec_responses:
            return AckMessage.STATUS_OK, 'OK'
        
        # 如果响应为空但有图片URL，显示图片URL
        if not response and image_url:
            response = f"图片已生成: {image_url}"
        
        response = response or "处理完成"
        
        self._reply_text(response[:1000], msg)
        return AckMessage.STATUS_OK, 'OK'


CHATBOT_TOPIC = "/v1.0/im/bot/messages/get"


def main():
    credential = Credential(CLIENT_ID, CLIENT_SECRET)
    client = dingtalk_stream.DingTalkStreamClient(credential)
    handler = AutoBotHandler(client)
    client.register_callback_handler(CHATBOT_TOPIC, handler)
    logger.info("钉钉机器人启动...")
    print("🤖 AutoBot 启动")
    client.start_forever()


if __name__ == "__main__":
    main()
