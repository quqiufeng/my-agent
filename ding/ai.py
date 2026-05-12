#!/usr/bin/env python3
"""
AI 模块 - 调用本地 OpenCode HTTP API

用法:
    from ai import AI
    ai = AI()
    result = ai.analyze("生成一张美女图")
    # result: {"plan": [], "summary": "..."}
"""
import json
import re
import requests

from logger import ai_logger as logger
from prompt import get_system_prompt


class AI:
    """AI 模块：调用本地 OpenCode HTTP API 分析任务"""

    # OpenCode Server 配置
    OPENCODE_BASE = "http://localhost:4097"

    def __init__(self):
        pass

    def analyze(self, task: str, context=None) -> dict:
        """分析任务，返回执行计划"""
        system_prompt = get_system_prompt()
        full_prompt = f"{system_prompt}\n\n用户任务: {task}"

        logger.info(f"Task: {task}")

        try:
            content = self._call_opencode(full_prompt)
            logger.info(f"DEBUG OpenCode 返回 content: {content[:500]}")
            return self._parse_response(content)
        except Exception as e:
            logger.error(f"OpenCode HTTP 调用异常: {e}")
            return {"plan": [], "summary": f"调用失败: {str(e)}"}

    def _call_opencode(self, prompt: str) -> str:
        """调用本地 OpenCode HTTP API"""
        # 1. 获取所有 session，使用第一个可用 session
        resp = requests.get(f"{self.OPENCODE_BASE}/session", timeout=5)
        sessions = resp.json()

        if not sessions:
            raise Exception(
                "没有可用的 opencode session，请先启动:\n"
                "tmux new-session -d -s opencode-dev 'opencode serve --port 4097'\n"
                "tmux new-window -t opencode-dev -n tui 'opencode attach http://localhost:4097'"
            )

        session_id = sessions[0]["id"]
        logger.info(f"使用 opencode session: {session_id}")

        # 2. 发送消息并等待返回
        resp = requests.post(
            f"{self.OPENCODE_BASE}/session/{session_id}/message",
            json={"parts": [{"type": "text", "text": prompt}]},
            timeout=120
        )

        result = resp.json()

        # 3. 从返回结果中提取文本内容
        parts = result.get("parts", [])
        for part in parts:
            if part.get("type") == "text":
                return part.get("text", "")

        raise Exception("OpenCode 返回结果中没有文本内容")

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

    def analyze_image(self, image_url: str, prompt: str = None) -> dict:
        """分析图片 - 使用 opencode 本地模型"""
        if prompt is None:
            prompt = """请非常详细地描述这张图片，包括：
1. 图片中的所有内容（人物、动物、物体、场景等）
2. 颜色、光线、构图
3. 背景环境（室内/室外、地点、时间等）
4. 整体风格和氛围
5. 任何有趣的细节

请用尽可能详细、生动、具体的语言描述，越详细越好！"""

        full_prompt = f"{prompt}\n\n图片 URL: {image_url}"

        logger.info(f"图片分析: {image_url[:50]}...")

        try:
            content = self._call_opencode(full_prompt)
            logger.info(f"图片分析结果: {content[:200]}")
            return {"plan": [], "summary": content}
        except Exception as e:
            return {"plan": [], "summary": f"图片分析失败: {str(e)}"}


if __name__ == "__main__":
    ai = AI()
    result = ai.analyze("生成一张美女图")
    logger.info(json.dumps(result, indent=2, ensure_ascii=False))
