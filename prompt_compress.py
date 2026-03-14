"""
提示词压缩模块
使用 zlib 压缩 + base64 编码，在系统提示词中告诉模型如何解压
"""

import base64
import zlib
import json
from typing import Dict, Any

COMPRESS_PREFIX = "【COMPRESSED]"
SYSTEM_PROMPT = """你是一个智能助手。当你收到以【COMPRESSED】开头的消息时，说明内容经过了压缩。

解压步骤：
1. 找到最后一个 ```json 代码块
2. 提取其中的 "p" 字段（base64 编码的压缩数据）
3. 用 base64 解码得到 bytes
4. 用 zlib decompress 解压得到原始提示词
5. 执行解压后的提示词指令

示例：
压缩后的格式：
```json
{"p": "eJwLSS0u0c1IzcnJBwALAAf..."}
```

请按上述步骤解压并执行。"""


def compress(prompt: str) -> str:
    """压缩提示词"""
    # zlib 压缩 (压缩级别 9)
    compressed = zlib.compress(prompt.encode("utf-8"), level=9)
    # base64 编码
    encoded = base64.b64encode(compressed).decode("ascii")
    # 包装成 JSON
    wrapper = json.dumps({"p": encoded})
    return f"{COMPRESS_PREFIX}\n```json\n{wrapper}\n```"


def decompress(compressed_prompt: str) -> str:
    """解压提示词（供测试用）"""
    if not compressed_prompt.startswith(COMPRESS_PREFIX):
        return compressed_prompt

    # 提取 JSON
    import re

    match = re.search(r"```json\s*(\{.*?\})\s*```", compressed_prompt, re.DOTALL)
    if not match:
        raise ValueError("无法找到压缩数据")

    data = json.loads(match.group(1))
    encoded = data["p"]

    # base64 解码 + zlib 解压
    compressed = base64.b64decode(encoded)
    return zlib.decompress(compressed).decode("utf-8")


def test_compress():
    """测试压缩效果"""
    original = """你是一个Python编程助手。请用Python实现一个红黑树，包含：
1. 插入操作
2. 删除操作
3. 查询操作
4. 中序遍历
5. 代码注释

请给出完整代码。"""

    compressed = compress(original)
    print(f"原始长度: {len(original)} 字符")
    print(f"压缩后长度: {len(compressed)} 字符")
    print(f"压缩比: {len(compressed) / len(original):.2%}")
    print()
    print("压缩后内容:")
    print(compressed[:200] + "...")
    print()

    # 测试解压
    decompressed = decompress(compressed)
    print("解压后内容:")
    print(decompressed)
    print()
    print("解压验证:", "✅ 成功" if original == decompressed else "❌ 失败")


if __name__ == "__main__":
    test_compress()
