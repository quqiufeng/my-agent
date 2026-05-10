#BY|# AutoBot AI 模块 - 硅基流动
import json
import requests
from config import Config, MODELS
from logger import ai_logger as logger
from prompt import get_system_prompt
import json
import requests
from config import Config, MODELS
from logger import ai_logger as logger


class AI:
    """AI 模块：调用硅基流动 API 分析任务"""
    
    def __init__(self, api_key=None, model_key=None):
        self.api_key = api_key or Config.API_KEY
        if model_key and model_key in MODELS:
            self.model = MODELS[model_key]["id"]
            self.model_key = model_key
        elif model_key:
            self.model = model_key
            self.model_key = None
        else:
            self.model = Config.get_model_id()
            self.model_key = Config.MODEL_KEY
        self.api_base = "https://api.siliconflow.cn/v1"
        
    def analyze(self, task, context=None):
        """分析任务，返回执行计划"""
        system_prompt = get_system_prompt()
        
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": task}
        ]
        
        url = f"{self.api_base}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        data = {
            "model": self.model,
            "messages": messages,
            "temperature": 0.7
        }
        
        logger.info(f"Task: {task}")
        
        try:
            response = requests.post(url, json=data, headers=headers, timeout=60)
            result = response.json()
            
            # 检查 result 类型
            if not isinstance(result, dict):
                logger.error(f"API 返回非字典类型: {type(result)}, 内容: {str(result)[:500]}")
                return {"plan": [], "summary": f"API 返回格式错误: {str(result)[:500]}"}
            
            content = result.get("choices", [{}])[0].get("message", {}).get("content", "")
            logger.info(f"DEBUG API 返回 content: {content[:500]}")
            
            # 解析返回
            try:
                import ast
                return ast.literal_eval(content)
            except Exception:
                try:
                    return json.loads(content)
                except Exception:
                    import re
                    json_match = re.search(r'\{[^{}]*\}', content, re.DOTALL)
                    if json_match:
                        try:
                            return json.loads(json_match.group())
                        except Exception:
                            pass
                    return {"plan": [], "summary": content}
        except Exception as e:
            logger.error(f"AI 调用异常: {e}")
            return {"plan": [], "summary": f"调用失败: {str(e)}"}

    def analyze_image(self, image_url, prompt=None):
        """分析图片 - 使用视觉模型"""
        # 更详细的 prompt
        if prompt is None:
            prompt = """请非常详细地描述这张图片，包括：
1. 图片中的所有内容（人物、动物、物体、场景等）
2. 颜色、光线、构图
3. 背景环境（室内/室外、地点、时间等）
4. 整体风格和氛围
5. 任何有趣的细节

请用尽可能详细、生动、具体的语言描述，越详细越好！"""
        
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": image_url}},
                    {"type": "text", "text": prompt}
                ]
            }
        ]
        
        url = f"{self.api_base}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        # 使用 Qwen VL 模型
        vision_model = "Qwen/Qwen2-VL-72B-Instruct"
        
        data = {
            "model": vision_model,
            "messages": messages,
            "temperature": 0.8  # 提高温度让描述更详细
        }
        
        logger.info(f"图片分析: {image_url[:50]}...")
        
        try:
            response = requests.post(url, json=data, headers=headers, timeout=180)
            result = response.json()
            
            content = result.get("choices", [{}])[0].get("message", {}).get("content", "")
            logger.info(f"图片分析结果: {content[:200]}")
            return {"plan": [], "summary": content}
        except Exception as e:
            return {"plan": [], "summary": f"图片分析失败: {str(e)}"}


if __name__ == "__main__":
    ai = AI()
    result = ai.analyze("生成一张美女图")
    logger.info(json.dumps(result, indent=2, ensure_ascii=False))
