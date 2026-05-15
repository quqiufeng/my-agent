#!/usr/bin/env python3
"""
微信 Bot API 封装 - iLink 协议

功能：
- QR 码登录、bot_token 持久化
- 长轮询收消息 (getupdates)
- 发送消息 (sendmessage) - 支持文本/图片/文件/语音/视频
- 媒体文件 AES-128-ECB 加解密 + CDN 上传下载
- 发送"正在输入"状态

文档：https://github.com/hao-ji-xing/openclaw-weixin
"""
import os
import sys
import json
import base64
import struct
import random
import time
import hashlib
import logging
import requests
from Crypto.Cipher import AES
from typing import Optional, Dict, List, Tuple

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from config import Config
from logger import app_logger as logger


BASE_URL = "https://ilinkai.weixin.qq.com"
CDN_BASE_URL = "https://novac2c.cdn.weixin.qq.com/c2c"

TOKEN_FILE = os.path.join(os.path.expanduser("~"), ".weixin_bot_token.json")


def _generate_uin() -> str:
    """生成 X-WECHAT-UIN：随机 uint32 转十进制字符串后 base64 编码"""
    rand_val = random.randint(0, 4294967295)
    return base64.b64encode(str(rand_val).encode()).decode()


def _make_headers(bot_token: str = "") -> dict:
    """构造请求头"""
    headers = {
        "Content-Type": "application/json",
        "AuthorizationType": "ilink_bot_token",
        "X-WECHAT-UIN": _generate_uin(),
    }
    if bot_token:
        headers["Authorization"] = f"Bearer {bot_token}"
    return headers


def _api_post(endpoint: str, body: dict, bot_token: str = "", timeout: int = 60) -> dict:
    """POST 请求封装"""
    url = f"{BASE_URL}/{endpoint}"
    headers = _make_headers(bot_token)
    try:
        resp = requests.post(url, json=body, headers=headers, timeout=timeout)
        resp.raise_for_status()
        return resp.json()
    except requests.exceptions.RequestException as e:
        logger.error(f"[WeixinAPI] POST {endpoint} 失败: {e}")
        return {"ret": -1, "error": str(e)}


def _api_get(endpoint: str, params: dict = None, bot_token: str = "", timeout: int = 30) -> dict:
    """GET 请求封装"""
    url = f"{BASE_URL}/{endpoint}"
    headers = _make_headers(bot_token)
    try:
        resp = requests.get(url, params=params, headers=headers, timeout=timeout)
        resp.raise_for_status()
        return resp.json()
    except requests.exceptions.RequestException as e:
        logger.error(f"[WeixinAPI] GET {endpoint} 失败: {e}")
        return {"ret": -1, "error": str(e)}


# ==================== AES-128-ECB 加解密 ====================

def _pad_pkcs7(data: bytes) -> bytes:
    """PKCS7 填充"""
    pad_len = 16 - (len(data) % 16)
    return data + bytes([pad_len] * pad_len)


def _unpad_pkcs7(data: bytes) -> bytes:
    """PKCS7 去填充"""
    pad_len = data[-1]
    return data[:-pad_len]


def encrypt_aes_ecb(plaintext: bytes, key: bytes) -> bytes:
    """AES-128-ECB 加密"""
    cipher = AES.new(key, AES.MODE_ECB)
    padded = _pad_pkcs7(plaintext)
    return cipher.encrypt(padded)


def decrypt_aes_ecb(ciphertext: bytes, key: bytes) -> bytes:
    """AES-128-ECB 解密"""
    cipher = AES.new(key, AES.MODE_ECB)
    decrypted = cipher.decrypt(ciphertext)
    return _unpad_pkcs7(decrypted)


def generate_aes_key() -> bytes:
    """生成随机 AES-128 key"""
    return os.urandom(16)


# ==================== 微信 Bot API 类 ====================

class WeixinBot:
    """微信 Bot API 封装"""
    
    def __init__(self, token_file: str = TOKEN_FILE):
        self.token_file = token_file
        self.bot_token = ""
        self.base_url = BASE_URL
        self.get_updates_buf = ""
        self._load_token()
    
    # ---------- Token 持久化 ----------
    
    def _load_token(self) -> bool:
        """从文件加载 bot_token"""
        if os.path.exists(self.token_file):
            try:
                with open(self.token_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    self.bot_token = data.get("bot_token", "")
                    self.base_url = data.get("baseurl", BASE_URL)
                    if self.bot_token:
                        logger.info("[WeixinBot] 已从文件加载 bot_token")
                        return True
            except Exception as e:
                logger.error(f"[WeixinBot] 加载 token 文件失败: {e}")
        return False
    
    def _save_token(self, bot_token: str, baseurl: str = "") -> None:
        """保存 bot_token 到文件"""
        self.bot_token = bot_token
        self.base_url = baseurl or BASE_URL
        try:
            with open(self.token_file, "w", encoding="utf-8") as f:
                json.dump({
                    "bot_token": bot_token,
                    "baseurl": self.base_url,
                    "saved_at": time.strftime("%Y-%m-%d %H:%M:%S")
                }, f, ensure_ascii=False, indent=2)
            logger.info("[WeixinBot] bot_token 已保存到文件")
        except Exception as e:
            logger.error(f"[WeixinBot] 保存 token 失败: {e}")
    
    def clear_token(self) -> None:
        """清除保存的 token（重新登录时使用）"""
        self.bot_token = ""
        self.base_url = BASE_URL
        if os.path.exists(self.token_file):
            try:
                os.remove(self.token_file)
                logger.info("[WeixinBot] token 文件已清除")
            except Exception as e:
                logger.error(f"[WeixinBot] 清除 token 失败: {e}")
    
    def is_logged_in(self) -> bool:
        """检查是否已登录"""
        return bool(self.bot_token)
    
    # ---------- 登录流程 ----------
    
    def get_qrcode(self) -> Tuple[str, str]:
        """
        获取登录二维码
        
        Returns:
            (qrcode, qrcode_img_content) - qrcode_img_content 是 base64 编码的图片
        """
        result = _api_get("ilink/bot/get_bot_qrcode", {"bot_type": "3"})
        if result.get("ret", 0) != 0:
            logger.error(f"[WeixinBot] 获取二维码失败: {result}")
            return "", ""
        
        qrcode = result.get("qrcode", "")
        img_content = result.get("qrcode_img_content", "")
        logger.info(f"[WeixinBot] 二维码已获取: {qrcode[:20]}...")
        return qrcode, img_content
    
    def check_qrcode_status(self, qrcode: str) -> dict:
        """
        检查扫码状态
        
        Returns:
            {"status": "pending|scanned|confirmed|expired", "bot_token": "...", "baseurl": "..."}
        """
        result = _api_get("ilink/bot/get_qrcode_status", {"qrcode": qrcode})
        status = result.get("status", "unknown")
        
        if status == "confirmed":
            bot_token = result.get("bot_token", "")
            baseurl = result.get("baseurl", "")
            if bot_token:
                self._save_token(bot_token, baseurl)
                logger.info("[WeixinBot] 扫码登录成功")
        
        return result
    
    def login(self, timeout: int = 300) -> bool:
        """
        完整的登录流程（获取二维码 → 等待扫码）
        
        Args:
            timeout: 最长等待时间（秒）
            
        Returns:
            是否登录成功
        """
        if self.is_logged_in():
            logger.info("[WeixinBot] 已登录，跳过扫码")
            return True
        
        qrcode, img_content = self.get_qrcode()
        if not qrcode:
            logger.error("[WeixinBot] 获取二维码失败")
            return False
        
        # 保存二维码图片到临时文件，方便用户扫码
        if img_content:
            img_path = "/tmp/weixin_qrcode.png"
            try:
                with open(img_path, "wb") as f:
                    f.write(base64.b64decode(img_content))
                logger.info(f"[WeixinBot] 二维码已保存到: {img_path}")
                print(f"\n📱 请用微信扫码登录: {img_path}\n")
            except Exception as e:
                logger.error(f"[WeixinBot] 保存二维码图片失败: {e}")
        
        print(f"⏳ 等待扫码登录...（最长 {timeout} 秒）")
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            result = self.check_qrcode_status(qrcode)
            status = result.get("status", "")
            
            if status == "confirmed":
                print("✅ 扫码登录成功！")
                return True
            elif status == "scanned":
                print("👀 已扫码，等待确认...")
            elif status == "expired":
                print("❌ 二维码已过期，请重新启动")
                return False
            
            time.sleep(2)
        
        print("⏰ 登录超时，请重新启动")
        return False
    
    # ---------- 消息收取 ----------
    
    def get_updates(self, timeout: int = 40) -> List[dict]:
        """
        长轮询收取消息
        
        Args:
            timeout: 请求超时时间（秒），建议比服务器 hold 时间稍长
            
        Returns:
            消息列表 (WeixinMessage[])
        """
        if not self.is_logged_in():
            logger.error("[WeixinBot] 未登录，无法收取消息")
            return []
        
        body = {
            "get_updates_buf": self.get_updates_buf,
            "base_info": {"channel_version": "1.0.2"}
        }
        
        result = _api_post("ilink/bot/getupdates", body, self.bot_token, timeout=timeout)
        
        if result.get("ret", 0) != 0:
            error = result.get("error", "未知错误")
            logger.error(f"[WeixinBot] 收取消息失败: {error}")
            return []
        
        # 更新游标
        new_buf = result.get("get_updates_buf", "")
        if new_buf:
            self.get_updates_buf = new_buf
        
        msgs = result.get("msgs", [])
        if msgs:
            logger.info(f"[WeixinBot] 收到 {len(msgs)} 条消息")
        
        return msgs
    
    # ---------- 发送消息 ----------
    
    def send_text(self, to_user_id: str, text: str, context_token: str) -> bool:
        """
        发送文本消息
        
        Args:
            to_user_id: 目标用户 ID (xxx@im.wechat)
            text: 消息内容
            context_token: 从收到的消息中获取，必须原样带上
            
        Returns:
            是否发送成功
        """
        if not self.is_logged_in():
            logger.error("[WeixinBot] 未登录，无法发送消息")
            return False
        
        msg = {
            "to_user_id": to_user_id,
            "message_type": 2,  # BOT 发出
            "message_state": 2,  # FINISH
            "context_token": context_token,
            "item_list": [
                {"type": 1, "text_item": {"text": text}}
            ]
        }
        
        result = _api_post("ilink/bot/sendmessage", {"msg": msg}, self.bot_token, timeout=30)
        
        if result.get("ret", 0) == 0:
            logger.info(f"[WeixinBot] 文本消息已发送给 {to_user_id}")
            return True
        else:
            logger.error(f"[WeixinBot] 发送消息失败: {result}")
            return False
    
    def send_markdown(self, to_user_id: str, markdown_text: str, context_token: str) -> bool:
        """
        发送 Markdown 格式消息（微信会渲染为富文本）
        
        注意：微信对 Markdown 的支持有限，建议主要用于代码块等简单格式
        """
        # 微信的文本消息支持部分 Markdown 语法
        return self.send_text(to_user_id, markdown_text, context_token)
    
    def send_image(self, to_user_id: str, image_path: str, context_token: str) -> bool:
        """
        发送图片消息
        
        流程：
        1. 读取图片文件
        2. 生成 AES key 并加密
        3. 获取 CDN 上传地址
        4. PUT 上传到 CDN
        5. 发送消息引用 CDN 文件
        """
        if not self.is_logged_in():
            logger.error("[WeixinBot] 未登录，无法发送图片")
            return False
        
        if not os.path.exists(image_path):
            logger.error(f"[WeixinBot] 图片文件不存在: {image_path}")
            return False
        
        try:
            # 1. 读取并加密图片
            with open(image_path, "rb") as f:
                image_data = f.read()
            
            aes_key = generate_aes_key()
            encrypted_data = encrypt_aes_ecb(image_data, aes_key)
            
            # 2. 获取上传地址
            upload_result = _api_post(
                "ilink/bot/getuploadurl",
                {
                    "file_name": os.path.basename(image_path),
                    "file_size": len(encrypted_data),
                    "file_type": "image"
                },
                self.bot_token
            )
            
            if upload_result.get("ret", 0) != 0:
                logger.error(f"[WeixinBot] 获取上传地址失败: {upload_result}")
                return False
            
            upload_url = upload_result.get("upload_url", "")
            if not upload_url:
                logger.error("[WeixinBot] 上传地址为空")
                return False
            
            # 3. 上传到 CDN
            upload_resp = requests.put(upload_url, data=encrypted_data, timeout=60)
            if upload_resp.status_code not in [200, 204]:
                logger.error(f"[WeixinBot] CDN 上传失败: HTTP {upload_resp.status_code}")
                return False
            
            # 4. 发送消息（带上 aes_key）
            msg = {
                "to_user_id": to_user_id,
                "message_type": 2,
                "message_state": 2,
                "context_token": context_token,
                "item_list": [
                    {
                        "type": 2,
                        "image_item": {
                            "aes_key": base64.b64encode(aes_key).decode(),
                            "cdn_url": upload_url
                        }
                    }
                ]
            }
            
            result = _api_post("ilink/bot/sendmessage", {"msg": msg}, self.bot_token)
            
            if result.get("ret", 0) == 0:
                logger.info(f"[WeixinBot] 图片已发送给 {to_user_id}")
                return True
            else:
                logger.error(f"[WeixinBot] 发送图片消息失败: {result}")
                return False
                
        except Exception as e:
            logger.error(f"[WeixinBot] 发送图片异常: {e}")
            return False
    
    # ---------- 正在输入状态 ----------
    
    def send_typing(self, to_user_id: str, context_token: str) -> bool:
        """发送"正在输入"状态"""
        if not self.is_logged_in():
            return False
        
        # 先获取 typing_ticket
        config_result = _api_post("ilink/bot/getconfig", {}, self.bot_token)
        if config_result.get("ret", 0) != 0:
            return False
        
        typing_ticket = config_result.get("typing_ticket", "")
        if not typing_ticket:
            return False
        
        body = {
            "to_user_id": to_user_id,
            "typing_ticket": typing_ticket,
            "context_token": context_token
        }
        
        result = _api_post("ilink/bot/sendtyping", body, self.bot_token)
        return result.get("ret", 0) == 0
    
    # ---------- 媒体下载 ----------
    
    def download_media(self, cdn_url: str, aes_key_b64: str, output_path: str) -> bool:
        """
        下载并解密媒体文件
        
        Args:
            cdn_url: CDN 下载地址
            aes_key_b64: base64 编码的 AES key
            output_path: 保存路径
            
        Returns:
            是否下载成功
        """
        try:
            resp = requests.get(cdn_url, timeout=60)
            if resp.status_code != 200:
                logger.error(f"[WeixinBot] 下载媒体失败: HTTP {resp.status_code}")
                return False
            
            encrypted_data = resp.content
            aes_key = base64.b64decode(aes_key_b64)
            decrypted_data = decrypt_aes_ecb(encrypted_data, aes_key)
            
            with open(output_path, "wb") as f:
                f.write(decrypted_data)
            
            logger.info(f"[WeixinBot] 媒体文件已下载: {output_path}")
            return True
            
        except Exception as e:
            logger.error(f"[WeixinBot] 下载媒体异常: {e}")
            return False


# ==================== 全局实例 ====================

_weixin_bot: Optional[WeixinBot] = None


def get_weixin_bot() -> WeixinBot:
    """获取微信 Bot 单例"""
    global _weixin_bot
    if _weixin_bot is None:
        _weixin_bot = WeixinBot()
    return _weixin_bot


def reset_weixin_bot() -> None:
    """重置微信 Bot 实例（用于重新登录）"""
    global _weixin_bot
    _weixin_bot = None


# ==================== 测试代码 ====================

if __name__ == "__main__":
    # 测试登录流程
    bot = WeixinBot()
    
    if bot.is_logged_in():
        print("✅ 已登录，准备收取消息...")
        msgs = bot.get_updates(timeout=10)
        print(f"收到 {len(msgs)} 条消息")
        for msg in msgs:
            print(json.dumps(msg, ensure_ascii=False, indent=2))
    else:
        print("🔄 未登录，开始扫码流程...")
        success = bot.login(timeout=300)
        if success:
            print("🎉 登录成功！")
        else:
            print("❌ 登录失败")
