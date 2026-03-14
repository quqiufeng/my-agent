import re


class UTEL_Encoder:
    def __init__(self):
        # 1. 自然语言映射表 (NL-Protocol) - 简体中文版
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
        }

    def _nl_encode(self, text):
        """自然语言：字典顺序替换"""
        for k, v in self.nl_dict.items():
            text = text.replace(k, v)
        return text

    def _code_encode(self, code):
        """代码：1:1 脱水逻辑，确保缩进和符号绝对准确"""
        lines = code.split("\n")
        compressed_lines = []

        for line in lines:
            # 即使是空行也要保留，以防 1:1 还原时丢失结构
            if not line.strip():
                compressed_lines.append("")
                continue

            # A. 处理缩进：默认 4 空格 = 1 个点
            leading_spaces = len(line) - len(line.lstrip())
            indent = "." * (leading_spaces // 4)

            content = line.strip()

            # B. 关键字替换 (正则 \b 确保单词边界安全)
            for k, v in self.code_keywords.items():
                content = re.sub(rf"\b{k}\b", v, content)

            # C. 符号空格处理 (1:1 核心：将空格转为下划线，防止大模型丢失空格)
            # 先处理自然语言注释部分的拼音转化
            if "#" in content:
                parts = content.split("#", 1)
                comment = self._nl_encode(parts[1])
                code_part = parts[0].replace(" ", "_")
                content = f"{code_part}#_{comment}"
            else:
                content = content.replace(" ", "_")

            compressed_lines.append(f"{indent}{content}")

        return "\n".join(compressed_lines)

    def pack(self, nl_input, code_input):
        """打包成最终 Prompt"""
        return (
            "【UTEL v3.2 压缩包】\n"
            f"自然语言：{self._nl_encode(nl_input)}\n"
            f"代码：\n#code\n{self._code_encode(code_input)}\n#end\n"
            "指令：1. 1:1 机械还原。2. 根据需求理解给出完整实现。"
        )


# --- 实战测试 ---
if __name__ == "__main__":
    encoder = UTEL_Encoder()

    test_nl = "请帮我实现一个高效的红黑树数据架构，包含插入逻辑。"
    test_code = """class RedBlackTree:
    def __init__(self):
        self.root = None # 初始化逻辑"""

    print(encoder.pack(test_nl, test_code))
