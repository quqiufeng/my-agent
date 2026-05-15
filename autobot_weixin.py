#!/usr/bin/env python3
"""
微信 Bot 主进程 - 长轮询消息收取 + 任务分发

架构：
- 主进程：长轮询收取微信消息，通过 Unix Domain Socket 发送给 Worker
- Worker 进程：复用 ding/task_worker.py

支持消息类型：
- text:      文本消息 (含 #指令)
- picture:   图片消息
- file:      文件消息
- voice:     语音消息
- video:     视频消息

启动方式：
    python autobot_weixin.py
"""
import os
import sys
import time
import uuid
import re
import json
import signal
import tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(SCRIPT_DIR, "ding"))

from weixin import WeixinBot, get_weixin_bot
from task_queue import TaskClient
from logger import app_logger as logger

# 懒加载，避免启动时加载
_voice_recognition = None


def _get_voice_recognition():
    """懒加载语音识别模块"""
    global _voice_recognition
    if _voice_recognition is None:
        import voice_recognition
        _voice_recognition = voice_recognition
    return _voice_recognition


class WeixinBotHandler:
    """微信消息处理器"""
    
    def __init__(self):
        self.task_client = TaskClient()
        self.weixin = get_weixin_bot()
        self._running = True
    
    def dispatch_task(self, task_type, content, timeout=60):
        """通过 Socket 发送任务并等待结果"""
        task_id = str(uuid.uuid4())
        task = {
            "id": task_id,
            "type": task_type,
            "content": content,
            "session_webhook": None,  # 微信不使用 webhook
            "timestamp": time.time()
        }
        return self.task_client.dispatch_task(task, timeout=timeout)
    
    def _extract_text(self, msg):
        """从微信消息中提取文本"""
        item_list = msg.get("item_list", [])
        for item in item_list:
            if item.get("type") == 1 and "text_item" in item:
                return item["text_item"].get("text", "").strip()
        return ""
    
    def _reply_text(self, to_user_id, text, context_token):
        """回复文本消息（封装错误处理）"""
        try:
            self.weixin.send_text(to_user_id, text[:1000], context_token)
        except Exception as e:
            logger.error(f"[WeixinBot] 回复消息失败: {e}")
    
    # ==================== 文本消息处理 ====================
    
    def _handle_text_message(self, msg, text):
        """处理文本消息"""
        from_user_id = msg.get("from_user_id", "")
        context_token = msg.get("context_token", "")
        
        # 匹配 #指令
        directive_match = re.match(r'#(\w+)', text)
        if directive_match:
            directive_name = directive_match.group(1)
            task_file = os.path.join(SCRIPT_DIR, "ding", "tasks", f"{directive_name}.py")
            
            if os.path.exists(task_file):
                logger.info(f"[WeixinBot] 执行指令: #{directive_name}")
                self._reply_text(from_user_id, "执行指令...", context_token)
                
                result = self.dispatch_task(
                    directive_name,
                    {"raw": text},
                    timeout=120
                )
                
                # 检查 Worker 是否已发送图片/Markdown
                exec_responses = result.get('exec_responses', '')
                if exec_responses and ('__MEDIA_ID__' in exec_responses or '__MARKDOWN_SENT__' in exec_responses):
                    return  # Worker 已处理
                
                # 回复文本结果
                output = result.get('stdout', '') or result.get('stderr', '') or result.get('error', '')
                if output:
                    self._reply_text(from_user_id, output[:1000], context_token)
                return
            else:
                self._reply_text(from_user_id, f"未知指令: #{directive_name}", context_token)
                return
        
        # 默认文字消息 -> ai_image 任务 (AI 对话)
        logger.info(f"[WeixinBot] 默认 AI 对话: {text[:100]}...")
        
        task_result = self.dispatch_task(
            "ai_image",
            {"user_input": text},
            timeout=180
        )
        
        exec_responses = task_result.get('exec_responses', '')
        response = ""
        
        if exec_responses:
            # 清理特殊标记
            clean_response = re.sub(r'📷 图片: https?://\S+', '', exec_responses)
            clean_response = re.sub(r'__MEDIA_ID__: \S+', '', clean_response)
            clean_response = re.sub(r'__LOCAL_IMAGE__: \S+', '', clean_response)
            clean_response = re.sub(r'__MARKDOWN_SENT__', '', clean_response)
            response = clean_response.strip()
        else:
            response = task_result.get('stdout', '') or task_result.get('error', '')
        
        response = response or "处理完成"
        self._reply_text(from_user_id, response[:1000], context_token)
    
    # ==================== 图片消息处理 ====================
    
    def _handle_image_message(self, msg):
        """处理图片消息"""
        from_user_id = msg.get("from_user_id", "")
        context_token = msg.get("context_token", "")
        
        self._reply_text(from_user_id, "📷 收到图片，正在分析...", context_token)
        
        try:
            # 从消息中提取图片信息
            item_list = msg.get("item_list", [])
            image_item = None
            for item in item_list:
                if item.get("type") == 2 and "image_item" in item:
                    image_item = item["image_item"]
                    break
            
            if not image_item:
                self._reply_text(from_user_id, "无法获取图片信息", context_token)
                return
            
            cdn_url = image_item.get("cdn_url", "")
            aes_key_b64 = image_item.get("aes_key", "")
            
            if not cdn_url or not aes_key_b64:
                self._reply_text(from_user_id, "图片信息不完整", context_token)
                return
            
            # 下载并解密图片
            temp_path = os.path.join(tempfile.gettempdir(), f"weixin_img_{int(time.time())}.jpg")
            
            if self.weixin.download_media(cdn_url, aes_key_b64, temp_path):
                # 调用 AI 分析图片
                # 注意：ai_image.py 的 _handle_image 需要 download_code（钉钉专用）
                # 这里我们先简单返回文件路径，后续可以扩展支持本地文件分析
                self._reply_text(from_user_id, f"图片已下载: {temp_path}\n图片分析功能开发中...", context_token)
                
                # TODO: 集成本地图片分析（JoyCaption）
                # 可以直接调用 image_analyzer.analyze_image(temp_path)
            else:
                self._reply_text(from_user_id, "图片下载失败", context_token)
                
        except Exception as e:
            logger.error(f"[WeixinBot] 处理图片消息异常: {e}")
            self._reply_text(from_user_id, "图片处理异常", context_token)
    
    # ==================== 文件消息处理 ====================
    
    def _handle_file_message(self, msg):
        """处理文件消息"""
        from_user_id = msg.get("from_user_id", "")
        context_token = msg.get("context_token", "")
        
        self._reply_text(from_user_id, "📎 收到文件，暂不支持文件分析", context_token)
    
    # ==================== 语音消息处理 ====================
    
    def _handle_voice_message(self, msg):
        """处理语音消息"""
        from_user_id = msg.get("from_user_id", "")
        context_token = msg.get("context_token", "")
        
        self._reply_text(from_user_id, "🎤 收到语音，正在识别...", context_token)
        
        try:
            # 从消息中提取语音信息
            item_list = msg.get("item_list", [])
            voice_item = None
            for item in item_list:
                if item.get("type") == 3 and "voice_item" in item:
                    voice_item = item["voice_item"]
                    break
            
            if not voice_item:
                self._reply_text(from_user_id, "无法获取语音信息", context_token)
                return
            
            cdn_url = voice_item.get("cdn_url", "")
            aes_key_b64 = voice_item.get("aes_key", "")
            recognized_text = voice_item.get("text", "")  # 微信可能已提供转文字结果
            
            # 如果微信已经提供了转文字结果，直接使用
            if recognized_text:
                logger.info(f"[WeixinBot] 微信已转文字: {recognized_text[:100]}")
                self._reply_text(from_user_id, f"📝 识别结果: {recognized_text[:200]}", context_token)
                # 将识别结果作为文本消息继续处理
                self._handle_text_message(msg, recognized_text)
                return
            
            # 否则尝试本地识别
            if not cdn_url or not aes_key_b64:
                self._reply_text(from_user_id, "语音信息不完整", context_token)
                return
            
            # 下载并解密语音文件
            temp_path = os.path.join(tempfile.gettempdir(), f"weixin_voice_{int(time.time())}.silk")
            
            if self.weixin.download_media(cdn_url, aes_key_b64, temp_path):
                # 微信语音是 silk 格式，需要先转换为 wav/amr
                # TODO: 集成 silk 解码器
                self._reply_text(from_user_id, "本地语音识别功能开发中...", context_token)
            else:
                self._reply_text(from_user_id, "语音下载失败", context_token)
                
        except Exception as e:
            logger.error(f"[WeixinBot] 处理语音消息异常: {e}")
            self._reply_text(from_user_id, "语音处理异常", context_token)
    
    # ==================== 消息分发 ====================
    
    def process_message(self, msg):
        """处理单条微信消息"""
        message_type = msg.get("message_type", 0)
        
        # message_type: 1 = 用户消息, 2 = Bot 自己发送的消息
        if message_type != 1:
            return  # 忽略自己发送的消息
        
        # 从 item_list 判断内容类型
        item_list = msg.get("item_list", [])
        if not item_list:
            return
        
        item_type = item_list[0].get("type", 0)
        
        try:
            if item_type == 1:
                # 文本消息
                text = self._extract_text(msg)
                if text:
                    self._handle_text_message(msg, text)
            elif item_type == 2:
                # 图片消息
                self._handle_image_message(msg)
            elif item_type == 3:
                # 语音消息
                self._handle_voice_message(msg)
            elif item_type == 4:
                # 文件消息
                self._handle_file_message(msg)
            elif item_type == 5:
                # 视频消息
                from_user_id = msg.get("from_user_id", "")
                context_token = msg.get("context_token", "")
                self._reply_text(from_user_id, "🎬 收到视频，暂不支持", context_token)
            else:
                # 未知类型
                from_user_id = msg.get("from_user_id", "")
                context_token = msg.get("context_token", "")
                self._reply_text(from_user_id, f"收到未知类型消息: {item_type}", context_token)
                
        except Exception as e:
            logger.error(f"[WeixinBot] 处理消息异常: {e}")
            try:
                from_user_id = msg.get("from_user_id", "")
                context_token = msg.get("context_token", "")
                self._reply_text(from_user_id, "消息处理异常，请稍后再试", context_token)
            except Exception:
                pass
    
    # ==================== 主循环 ====================
    
    def run(self):
        """主循环：长轮询收取消息"""
        logger.info("[WeixinBot] 主循环启动")
        print("🤖 微信 Bot 启动（基于长轮询）")
        print("   按 Ctrl+C 停止\n")
        
        consecutive_errors = 0
        
        while self._running:
            try:
                # 长轮询收取消息（timeout 40s，比服务器 35s 稍长）
                msgs = self.weixin.get_updates(timeout=40)
                consecutive_errors = 0  # 成功则重置错误计数
                
                for msg in msgs:
                    try:
                        self.process_message(msg)
                    except Exception as e:
                        logger.error(f"[WeixinBot] 处理消息异常: {e}")
                
            except Exception as e:
                consecutive_errors += 1
                logger.error(f"[WeixinBot] 长轮询异常 ({consecutive_errors}): {e}")
                
                # 连续错误超过 5 次，增加等待时间
                if consecutive_errors > 5:
                    wait_time = min(consecutive_errors * 5, 60)
                    logger.warning(f"[WeixinBot] 连续错误 {consecutive_errors} 次，等待 {wait_time}s 后重试")
                    time.sleep(wait_time)
                else:
                    time.sleep(5)
        
        logger.info("[WeixinBot] 主循环结束")
    
    def stop(self):
        """停止主循环"""
        self._running = False


# ==================== 全局处理器实例 ====================

handler = None


def signal_handler(signum, frame):
    """信号处理"""
    signame = signal.Signals(signum).name
    print(f"\n📴 收到信号 {signame}，正在停止...")
    global handler
    if handler:
        handler.stop()


def main():
    global handler
    
    # 初始化微信 Bot
    weixin = get_weixin_bot()
    
    if not weixin.is_logged_in():
        print("🔄 未登录，开始扫码流程...")
        success = weixin.login(timeout=300)
        if not success:
            print("❌ 登录失败，程序退出")
            return 1
    
    print("✅ 已登录，准备收取消息...")
    
    # 注册信号处理
    handler = WeixinBotHandler()
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # 启动主循环
    try:
        handler.run()
    except Exception as e:
        logger.error(f"[WeixinBot] 主进程异常: {e}")
        return 1
    
    print("👋 微信 Bot 已停止")
    return 0


if __name__ == "__main__":
    exit(main())
