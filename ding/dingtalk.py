#!/usr/bin/env python3
"""
钉钉统一 API 模块
功能：
- 获取 access_token
- 上传媒体文件
- 下载媒体文件
- 发送消息

官方文档：https://open.dingtalk.com/document/dingstart/robot-reply-and-send-messages
"""
import os
import sys
import requests

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from config import Config
from logger import app_logger as logger


class DingTalk:
    """钉钉统一 API 模块"""
    
    def __init__(self, client_id=None, client_secret=None):
        self.client_id = client_id or Config.DINGTALK_CLIENT_ID
        self.client_secret = client_secret or Config.DINGTALK_CLIENT_SECRET
        self.base_url = "https://api.dingtalk.com"
        self._token = None
        self._token_expires_at = 0
    
    def get_token(self):
        """获取 access_token（带缓存）"""
        import time
        now = time.time()
        
        # 检查缓存是否有效
        if self._token and now < self._token_expires_at:
            return self._token
        
        try:
            url = f"{self.base_url}/v1.0/oauth2/accessToken"
            data = {
                "appKey": self.client_id,
                "appSecret": self.client_secret
            }
            resp = requests.post(url, json=data, timeout=10)
            result = resp.json()
            
            if "accessToken" in result:
                self._token = result["accessToken"]
                # 提前5分钟过期
                self._token_expires_at = now + result.get("expireIn", 7200) - 300
                return self._token
            else:
                logger.error(f"获取 token 失败: {result}")
                return None
        except Exception as e:
            logger.error(f"获取 token 异常: {e}")
            return None
    
    def upload_media(self, media_type="file", file_path=None, file_content=None, filename="file"):
        """上传媒体文件
        
        Args:
            media_type: 媒体类型 (image/file)
            file_path: 本地文件路径
            file_content: 文件二进制内容
            filename: 文件名
            
        Returns:
            media_id 或 None
        """
        token = self.get_token()
        if not token:
            return None
        
        # 准备文件内容
        content = None
        if file_content:
            content = file_content
        elif file_path and os.path.exists(file_path):
            try:
                with open(file_path, "rb") as f:
                    content = f.read()
            except Exception as e:
                logger.error(f"读取文件失败: {e}")
                return None
        else:
            logger.error("未提供文件内容或路径")
            return None
        
        try:
            url = f"https://oapi.dingtalk.com/media/upload?access_token={token}&type={media_type}"
            
            # 根据媒体类型设置 MIME
            mime_type = "application/octet-stream"
            if media_type == "image":
                mime_type = "image/png"
            
            files = {'media': (filename, content, mime_type)}
            
            resp = requests.post(url, files=files, timeout=30)
            result = resp.json()
            
            if "media_id" in result:
                return result["media_id"]
            else:
                logger.error(f"上传媒体失败: {result}")
                return None
        except Exception as e:
            logger.error(f"上传媒体异常: {e}")
            return None
    
    def download_file(self, download_code, robot_code):
        """下载文件"""
        token = self.get_token()
        if not token:
            return None
        
        try:
            url = f"{self.base_url}/v1.0/robot/messageFiles/download"
            headers = {
                "Content-Type": "application/json",
                "x-acs-dingtalk-access-token": token
            }
            data = {
                "downloadCode": download_code,
                "robotCode": robot_code
            }
            resp = requests.post(url, json=data, headers=headers, timeout=30)
            result = resp.json()
            
            if "downloadUrl" in result:
                return result["downloadUrl"]
            else:
                logger.error(f"下载文件失败: {result}")
                return None
        except Exception as e:
            logger.error(f"下载文件异常: {e}")
            return None
    
    def send_text(self, webhook, content):
        """发送文本消息"""
        return self._send_message(webhook, {"msgtype": "text", "text": {"content": content}})
    
    def send_markdown(self, webhook, title, text):
        """发送 Markdown 消息"""
        return self._send_message(webhook, {
            "msgtype": "markdown",
            "markdown": {"title": title, "text": text}
        })
    
    def send_image(self, webhook, media_id):
        """发送图片消息"""
        return self._send_message(webhook, {"msgtype": "image", "image": {"media_id": media_id}})
    
    def send_markdown_image(self, webhook, media_id):
        """发送 Markdown 格式的图片消息（点击图片可放大）"""
        text = f"![AI图片]({media_id})"
        return self.send_markdown(webhook, "AI 生成图片", text)
    
    def _send_message(self, webhook, message):
        """发送消息"""
        try:
            resp = requests.post(webhook, json=message, timeout=10)
            result = resp.json()
            
            if result.get("errcode") == 0:
                return True
            else:
                logger.error(f"发送消息失败: {result}")
                return False
        except Exception as e:
            logger.error(f"发送消息异常: {e}")
            return False


# 便捷函数
def get_dingtalk():
    """获取 DingTalk 实例"""
    return DingTalk()


def upload_image(image_url_or_path):
    """上传图片（支持 URL 或本地路径）"""
    dingtalk = DingTalk()
    
    # 如果是 URL，先下载
    if image_url_or_path.startswith("http"):
        try:
            resp = requests.get(image_url_or_path, timeout=60)
            if resp.status_code == 200:
                content = resp.content
            else:
                logger.error(f"下载图片失败: HTTP {resp.status_code}")
                return None
        except Exception as e:
            logger.error(f"下载图片异常: {e}")
            return None
    else:
        # 本地文件
        try:
            with open(image_url_or_path, "rb") as f:
                content = f.read()
        except Exception as e:
            logger.error(f"读取图片失败: {e}")
            return None
    
    return dingtalk.upload_media("image", file_content=content, filename="image.png")


def send_image_message(webhook, image_url_or_path):
    """发送图片消息"""
    media_id = upload_image(image_url_or_path)
    if media_id:
        dingtalk = DingTalk()
        return dingtalk.send_image(webhook, media_id)
    return False
