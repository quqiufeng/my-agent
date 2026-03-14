import re


class UTEL_Encoder:
    def __init__(self):
        # 1. 自然语言映射表 (NL-Protocol)
        self.nl_dict = {
            "数据": "Shu-Ju",
            "架构": "Jia-Gu",
            "代码": "Dai-Ma",
            "要求": "Yao-Qiu",
            "实现": "Shi-Xian",
            "红黑树": "Hong-Hei-Shu",
            "插入": "Cha-Ru",
            "删除": "Shan-Chu",
            "查找": "Cha-Zhao",
            "遍历": "Bian-Li",
            "中序": "Zhong-Xu",
            "完整": "Wan-Zheng",
            "包含": "Bao-Kuo",
            "操作": "Cao-Zuo",
            "注释": "Zhu-Shi",
            "逻辑": "Luo-Ji",
            "复杂": "Fu-Za",
            "递归": "Di-Gui",
            "现代": "Xian-Dai",
            "语法": "Yu-Fa",
            "异步": "Yi-Bu",
            "并发": "Bing-Fa",
            "框架": "Kuang-Jia",
            "单文件": "Dan-Wen-Jian",
            "类似": "Lei-Si",
            "支持": "Zhi-Chi",
        }

        # 2. 代码关键字映射 (Code-Recovery)
        self.code_keywords = {
            "class": "cs5",
            "def": "df3",
            "if": "if2",
            "elif": "el4",
            "else": "es4",
            "return": "rn6",
            "while": "wh5",
            "for": "fr3",
            "import": "im6",
            "break": "bk5",
            "continue": "ce8",
            "self": "sf4",
            "async": "asy4",
            "await": "awa4",
            "try": "try2",
            "except": "exc5",
        }

    def _nl_encode(self, text):
        """自然语言：字典顺序替换"""
        for k, v in self.nl_dict.items():
            text = text.replace(k, v)
        return text

    def _code_encode(self, code):
        """代码：1:1 脱水逻辑"""
        lines = code.split("\n")
        compressed_lines = []

        for line in lines:
            if not line.strip():
                compressed_lines.append("")
                continue

            # 缩进处理
            leading_spaces = len(line) - len(line.lstrip())
            indent = "." * (leading_spaces // 4)

            content = line.strip()

            # 关键字替换
            for k, v in self.code_keywords.items():
                content = re.sub(rf"\b{k}\b", v, content)

            # 空格处理
            if "#" in content:
                parts = content.split("#", 1)
                comment = self._nl_encode(parts[1])
                code_part = parts[0].replace(" ", "_")
                content = f"{code_part}#_{comment}"
            else:
                content = content.replace(" ", "_")

            compressed_lines.append(f"{indent}{content}")

        return "\n".join(compressed_lines)

    def pack(self, full_text):
        """
        自动提取并压缩 full_text 中的 #code...#end 块
        只传一个 nl_input，自动匹配代码块
        """
        # 1. 提取所有 #code...#end 块
        code_blocks = re.findall(r"#code\n(.*?)\n#end", full_text, re.DOTALL)

        # 2. 压缩每个代码块
        compressed_blocks = []
        for code in code_blocks:
            compressed_blocks.append(self._code_encode(code))

        # 3. 替换原文中的代码块为压缩版本
        result = full_text
        for original, compressed in zip(code_blocks, compressed_blocks):
            result = result.replace(
                f"#code\n{original}\n#end", f"#code\n{compressed}\n#end"
            )

        # 4. 压缩自然语言部分
        result = self._nl_encode(result)

        return result


# --- 测试 ---
if __name__ == "__main__":
    encoder = UTEL_Encoder()

    # 测试：一次性输入全部内容
    test_input = """
请帮我实现一个单文件的python web框架。

#code
class Web:
    def __init__(self):
        self.routes = {}
    
    def route(self, path):
        def decorator(func):
            self.routes[path] = func
            return func
        return decorator
    
    async def handle(self, request):
        handler = self.routes.get(request.path)
        if handler:
            return await handler(request)
        return 404
#end

要求支持异步和并发。
"""

    print("=== 原始输入 ===")
    print(test_input)
    print("\n=== 压缩后 ===")
    print(encoder.pack(test_input))
