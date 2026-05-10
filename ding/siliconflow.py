#!/usr/bin/env python3
"""
硅基流动统一 API 模块
功能：
- 文本对话 (chat)
- 图片生成 (generate_image)
- 图片分析 (vision)
- 语音合成 (generate_speech)
- 语音识别 (transcribe)
- 视频生成 (generate_video)
- 获取视频状态 (get_video_status)
"""
import os
import sys
import json
import time
import requests

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from config import Config
from logger import app_logger as logger

API_KEY = Config.API_KEY
API_BASE = "https://api.siliconflow.cn/v1"


class SiliconFlow:
    """硅基流动统一 API 模块"""
    
    def __init__(self, api_key=None):
        self.api_key = api_key or API_KEY
        self.base_url = API_BASE
    
    def _request(self, method, endpoint, data=None, files=None, timeout=60):
        """统一请求方法"""
        url = f"{self.base_url}{endpoint}"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        try:
            if method == "GET":
                response = requests.get(url, headers=headers, timeout=timeout)
            elif method == "POST":
                if files:
                    response = requests.post(
                        url, 
                        headers={"Authorization": f"Bearer {self.api_key}"}, 
                        data=data, 
                        files=files, 
                        timeout=timeout
                    )
                else:
                    response = requests.post(url, headers=headers, json=data, timeout=timeout)
            
            return response.json()
        except Exception as e:
            return {"error": str(e)}

    # ========== 文本对话 ==========
    def chat(self, prompt, model="deepseek-ai/DeepSeek-V3.2", system_prompt=None, json_mode=False, **kwargs):
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})
        
        data = {
            "model": model,
            "messages": messages,
        }
        
        if json_mode:
            data["response_format"] = {"type": "json_object"}
        
        data.update(kwargs)
        
        result = self._request("POST", "/chat/completions", data)
        
        if "choices" in result:
            content = result["choices"][0]["message"]["content"]
            if kwargs.get("return_usage", False):
                return {"content": content, "usage": result.get("usage", {})}
            return content
        return result.get("error", str(result))

    # ========== 图片生成 ==========
    def generate_image(self, prompt, model="black-forest-labs/FLUX.1-dev", **kwargs):
        import hashlib
        
        data = {
            "model": model,
            "prompt": prompt,
        }
        data.update(kwargs)
        
        result = self._request("POST", "/images/generations", data, timeout=120)
        
        # 检查返回是否有效
        if result is None or not isinstance(result, dict):
            return {
                "success": False,
                "error": f"API 返回无效数据: {result}",
                "image_url": None,
                "local_path": None,
                "seed": None,
            }
        
        # 检查 API 业务错误 (如模型禁用)
        if result.get("code") == 30003 or result.get("code") == 20012:
            return {
                "success": False,
                "error": result.get("message", "模型不可用或已被禁用"),
                "image_url": None,
                "local_path": None,
                "seed": None,
            }
        
        if "data" in result and result["data"] and len(result["data"]) > 0:
            image_url = result["data"][0].get("url", "")
            seed = result["data"][0].get("seed", None)
            
            local_path = None
            if image_url:
                try:
                    img_response = requests.get(image_url, timeout=60)
                    if img_response.status_code == 200:
                        timestamp = str(int(time.time() * 1000))
                        random_str = hashlib.md5(timestamp.encode()).hexdigest()[:12]
                        local_path = os.path.join(SCRIPT_DIR, f"image_{random_str}.png")
                        
                        with open(local_path, "wb") as f:
                            f.write(img_response.content)
                except Exception as e:
                    logger.error(f"图片下载失败: {e}")
            
            return {
                "success": True,
                "image_url": image_url,
                "local_path": local_path,
                "seed": seed,
                "inference_time": result.get("timing", {})
            }
        
        return {
            "success": False,
            "error": result.get("error", result.get("message", str(result))),
            "image_url": None,
            "local_path": None,
            "seed": None,
            "inference_time": {}
        }

    # ========== 语音合成 ==========
    def generate_speech(self, text, model="iic/CosyVoice-3-7B-SFT", voice="axiaoxi", **kwargs):
        import hashlib
        
        data = {
            "model": model,
            "input": text,
            "voice": voice,
        }
        data.update(kwargs)
        
        result = self._request("POST", "/audio/speech", data, timeout=60)
        
        if hasattr(result, 'content'):
            timestamp = str(int(time.time() * 1000))
            random_str = hashlib.md5(timestamp.encode()).hexdigest()[:12]
            local_path = os.path.join(SCRIPT_DIR, f"speech_{random_str}.mp3")
            
            with open(local_path, "wb") as f:
                f.write(result.content)
            
            return {"success": True, "audio_url": None, "local_path": local_path}
        
        return {"success": False, "error": str(result), "audio_url": None, "local_path": None}

    # ========== 语音识别 ==========
    def transcribe(self, audio_path, model="iic/SenseVoiceSmall", **kwargs):
        try:
            with open(audio_path, "rb") as f:
                audio_data = f.read()
            
            files = {'file': ('audio.mp3', audio_data, 'audio/mpeg'), 'model': (None, model)}
            data = {}
            data.update(kwargs)
            
            result = self._request("POST", "/audio/transcriptions", data=data, files=files, timeout=120)
            
            if "text" in result:
                return result["text"]
            return result
        except Exception as e:
            return {"error": str(e)}

    # ========== 视频生成 ==========
    def generate_video(self, prompt, model="zeroscope_v2_576w", **kwargs):
        data = {"model": model, "prompt": prompt}
        data.update(kwargs)
        
        result = self._request("POST", "/video/generations", data, timeout=60)
        
        if "id" in result:
            return {"success": True, "video_id": result["id"], "status": result.get("status", "pending")}
        return {"success": False, "error": str(result), "video_id": None, "status": "failed"}

    # ========== 获取视频状态 ==========
    def get_video_status(self, video_id):
        result = self._request("GET", f"/video/generations/{video_id}")
        
        if "status" in result:
            return {"success": result["status"] == "succeed", "status": result["status"], "video_url": result.get("video_url")}
        return {"success": False, "status": "failed", "video_url": None}


# ========== 便捷函数 ==========
def chat(prompt, **kwargs):
    return SiliconFlow().chat(prompt, **kwargs)

def vision(prompt, image_url, **kwargs):
    return SiliconFlow().vision(prompt, image_url, **kwargs)

def generate_image(prompt, **kwargs):
    return SiliconFlow().generate_image(prompt, **kwargs)

def generate_speech(text, **kwargs):
    return SiliconFlow().generate_speech(text, **kwargs)

def transcribe(audio_path, **kwargs):
    return SiliconFlow().transcribe(audio_path, **kwargs)

def generate_video(prompt, **kwargs):
    return SiliconFlow().generate_video(prompt, **kwargs)


if __name__ == "__main__":
    sf = SiliconFlow()
    print(sf.chat("你好"))
