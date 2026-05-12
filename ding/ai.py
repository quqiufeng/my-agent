#!/usr/bin/env python3
"""
AI 模块 - 调用本地 OpenCode 替代硅基流动

用法:
    from ai import AI
    ai = AI()
    result = ai.analyze("生成一张美女图")
    # result: {"plan": [], "summary": "..."}
"""
import json
import re
import subprocess
import requests

from config import Config, MODELS
from logger import ai_logger as logger
from prompt import get_system_prompt


class AI:
    """AI 模块：调用本地 OpenCode CLI 分析任务"""

    # OpenCode 模型
    OPENCODE_MODEL = "kimi-for-coding/k2p6"
    # 硅基流动配置（fallback）
    SILICONFLOW_BASE = "https://api.siliconflow.cn/v1"

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

    def analyze(self, task: str, context=None) -> dict:
        """分析任务，返回执行计划 - 优先使用本地 OpenCode"""
        system_prompt = get_system_prompt()
        full_prompt = f"{system_prompt}\n\n用户任务: {task}"

        logger.info(f"Task: {task}")

        # 先尝试本地 OpenCode
        try:
            content = self._call_opencode(full_prompt)
            logger.info(f"DEBUG OpenCode 返回 content: {content[:500]}")
            return self._parse_response(content)
        except Exception as e:
            logger.error(f"OpenCode 调用异常: {e}")
            logger.info("Fallback 到硅基流动 API")
            return self._analyze_siliconflow(task, context)

    def _call_opencode(self, prompt: str) -> str:
        """调用本地 OpenCode CLI"""
        cmd = [
            "opencode", "run", prompt,
            "--model", self.OPENCODE_MODEL,
        ]

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,
            cwd="/home/dministrator/my-agent/ding"
        )

        if result.returncode != 0:
            stderr = result.stderr or ""
            raise Exception(f"opencode run 失败: {stderr[:500]}")

        # 清洗 ANSI 颜色代码
        output = self._strip_ansi(result.stdout)

        # 提取 AI 回复（去掉前缀如 "> build · k2p6"）
        lines = output.split("\n")
        content_lines = []
        for line in lines:
            line = line.strip()
            if not line:
                continue
            # 跳过 opencode 的元信息行
            if line.startswith(">") or line.startswith("$") or line.startswith("bash"):
                continue
            content_lines.append(line)

        return "\n".join(content_lines)

    @staticmethod
    def _strip_ansi(text: str) -> str:
        """移除 ANSI 转义序列"""
        ansi_escape = re.compile(r"\x1b\[[0-9;]*m")
        return ansi_escape.sub("", text)

    @staticmethod
    def _parse_response(content: str) -> dict:
        """解析 AI 返回内容"""
        try:
            import ast
            return ast.literal_eval(content)
        except Exception:
            try:
                return json.loads(content)
            except Exception:
                json_match = re.search(r"\{[^{}]*\}", content, re.DOTALL)
                if json_match:
                    try:
                        return json.loads(json_match.group())
                    except Exception:
                        pass
                return {"plan": [], "summary": content}

    def _analyze_siliconflow(self, task: str, context=None) -> dict:
        """Fallback：直接调用硅基流动 API"""
        system_prompt = get_system_prompt()

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": task}
        ]

        url = f"{self.SILICONFLOW_BASE}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        data = {
            "model": self.model,
            "messages": messages,
            "temperature": 0.7
        }

        try:
            response = requests.post(url, json=data, headers=headers, timeout=60)
            result = response.json()

            if not isinstance(result, dict):
                return {"plan": [], "summary": f"API 返回格式错误: {str(result)[:500]}"}

            content = result.get("choices", [{}])[0].get("message", {}).get("content", "")
            return self._parse_response(content)
        except Exception as e:
            return {"plan": [], "summary": f"调用失败: {str(e)}"}

    def analyze_image(self, image_url: str, prompt: str = None) -> dict:
        """分析图片 - 使用视觉模型（仍走硅基流动）"""
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

        url = f"{self.SILICONFLOW_BASE}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }

        vision_model = "Qwen/Qwen2-VL-72B-Instruct"
        data = {
            "model": vision_model,
            "messages": messages,
            "temperature": 0.8
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
