#!/usr/bin/env python3
"""子进程调用远程 API"""

import sys
import os
import json

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from api import chat
from prompt import build_user_prompt

user_input = sys.argv[1] if len(sys.argv) > 1 else ""

prompt = build_user_prompt(user_input)
result = chat(
    messages=[{"role": "user", "content": prompt}],
    source="minimax",
    max_tokens=8192,
)

# 输出 JSON 格式，避免编码问题
print(json.dumps({"result": result}, ensure_ascii=False))
