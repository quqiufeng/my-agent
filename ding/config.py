# AutoBot 配置模块

import os
from dotenv import load_dotenv

# 从脚本所在目录加载 .env
script_dir = os.path.dirname(os.path.abspath(__file__))
env_path = os.path.join(script_dir, '.env')
if os.path.exists(env_path):
    load_dotenv(env_path, override=True)

# 获取脚本所在目录
SCRIPT_DIR = script_dir


# ============ 硅基流动模型列表 ============
MODELS = {
    # 对话/推理模型
    "deepseek-v3.2": {"id": "deepseek-ai/DeepSeek-V3.2", "name": "DeepSeek V3.2", "type": "chat", "context": "64K", "price": "¥1/1M"},
    "deepseek-chat": {"id": "deepseek-ai/DeepSeek-Chat", "name": "DeepSeek Chat", "type": "chat", "context": "64K", "price": "¥0.5/1M"},
    "qwen-72b": {"id": "Qwen/Qwen2-72B-Instruct", "name": "Qwen 72B", "type": "chat", "context": "32K", "price": "¥8/1M"},
    "qwen-14b": {"id": "Qwen/Qwen2-14B-Instruct", "name": "Qwen 14B", "type": "chat", "context": "32K", "price": "¥1/1M"},
    "qwen-7b": {"id": "Qwen/Qwen2-7B-Instruct", "name": "Qwen 7B", "type": "chat", "context": "32K", "price": "¥0.4/1M"},
    "yi-34b": {"id": "01-ai/Yi-34B-Chat", "name": "Yi 34B", "type": "chat", "context": "32K", "price": "¥3/1M"},
    "kimi": {"id": "moonshotai/kimi-chat", "name": "Kimi", "type": "chat", "context": "128K", "price": "¥15/1M"},
    "kimi-k2.5": {"id": "Pro/moonshotai/Kimi-K2.5", "name": "Kimi K2.5", "type": "chat", "context": "128K", "price": "¥30/1M"},
    # 图像理解模型
    "kimi-vl": {"id": "moonshotai/Kimi-VL-A3B-Instruct", "name": "Kimi VL", "type": "vision", "context": "32K", "price": "¥3/1M"},
    "qwen-vl": {"id": "Qwen/Qwen2-VL-72B-Instruct", "name": "Qwen VL", "type": "vision", "context": "32K", "price": "¥8/1M"},
    # 图像生成模型
    "flux-dev": {"id": "black-forest-labs/FLUX.1-dev", "name": "FLUX.1 dev", "type": "image", "price": "¥4/张"},
    "flux-schnell": {"id": "black-forest-labs/FLUX.1-schnell", "name": "FLUX.1 schnell", "type": "image", "price": "¥0.4/张"},
    "sdxl": {"id": "stabilityai/stable-diffusion-xl-base-1.0", "name": "SDXL", "type": "image", "price": "¥0.5/张"},
    "playground-v2.5": {"id": "playgroundai/playground-v2.5-1024px-aesthetic", "name": "Playground v2.5", "type": "image", "price": "¥0.5/张"},
    # 语音合成模型
    "cosyvoice": {"id": "iic/CosyVoice-3-7B-SFT", "name": "CosyVoice", "type": "tts", "price": "¥1/1M"},
    "spear-tts": {"id": "google/spear-tts-mini_en", "name": "SpearTTS", "type": "tts", "price": "¥3/1M"},
    # 语音识别模型
    "sensevoice": {"id": "iic/SenseVoiceSmall", "name": "SenseVoice", "type": "stt", "price": "¥0.2/1M"},
    "whisper": {"id": "openai/whisper-large-v3", "name": "Whisper", "type": "stt", "price": "¥7.5/1M"},
    # Embedding 模型
    "bge-m3": {"id": "BAAI/bge-m3", "name": "BGE M3", "type": "embedding", "price": "¥0.2/1M"},
    "bge-large": {"id": "BAAI/bge-large-zh-v1.5", "name": "BGE Large", "type": "embedding", "price": "¥0.5/1M"},
    # 兼容别名
    "gpt-4": {"id": "deepseek-ai/DeepSeek-V3.2", "name": "DeepSeek V3.2 (gpt-4)", "type": "chat", "price": "¥1/1M"},
    "gpt-3.5": {"id": "deepseek-ai/DeepSeek-Chat", "name": "DeepSeek Chat (gpt-3.5)", "type": "chat", "price": "¥0.5/1M"},
}


# ============ 配置项 ============
DINGTALK_CLIENT_ID = os.getenv("DINGTALK_CLIENT_ID", "")
DINGTALK_CLIENT_SECRET = os.getenv("DINGTALK_CLIENT_SECRET", "")
API_KEY = os.getenv("SILICONFLOW_API_KEY", "")
MODEL_KEY = os.getenv("DEFAULT_MODEL", "deepseek-v3.2")
WORK_DIR = os.getenv("WORK_DIR", SCRIPT_DIR)
SANDBOX_DIR = os.getenv("SANDBOX_DIR", SCRIPT_DIR)
TIMEOUT = int(os.getenv("TIMEOUT", "300"))
HTTP_PROXY = os.getenv("HTTP_PROXY", "")
HTTPS_PROXY = os.getenv("HTTPS_PROXY", "")
GITHUB_REPO = os.getenv("GITHUB_REPO", "quqiufeng/my-game")


# ============ 安全配置 - 黑名单模式 ============
# 只禁止危险命令，其他都允许
FORBIDDEN_PATTERNS = [
    # 递归删除根目录
    r"rm -rf",
    r"rmdir -p",
    # 磁盘操作
    r"mkfs",
    r"dd if=",
    r"fdisk",
    r"parted",
    # 系统关机/重启
    r"^shutdown",
    r"^reboot",
    r"init 0",
    r"init 6",
    r"telinit",
    r"halt",
    r"poweroff",
    r"systemctl",
    # 防火墙
    r"iptables",
    r"ufw",
    r"firewall-cmd",
    # 网络后门/下载/主动连接
    r"nc -",
    r"ncat",
    r"socat",
    r"curl\s",
    r"wget\s",
    r"curl\|",
    r"wget\|",
    r"ssh\s",
    r"scp\s",
    r"sftp",
    r"ftp\s",
    # 容器/虚拟化
    r"docker",
    r"podman",
    r"kubectl",
    r"helm",
    r"minikube",
    # Shell 反弹
    r"bash -i",
    r"sh -i",
    r"dash -i",
    # 挖矿
    r"xmrig",
    r"miner",
    # 权限绕过
    r"chmod -R 777",
    r"chown -R",
    r"chattr \+i",
    # 后门检测
    r":\(\)\{:\|\&:\};:",
    # 提权
    r"^sudo",
    r"su -",
    r"su root",
]


def get_model_id():
    model = MODELS.get(MODEL_KEY)
    if model:
        return model["id"]
    return MODELS["deepseek-v3.2"]["id"]


# ============ 兼容旧版 Config 类 ============
class Config:
    DINGTALK_CLIENT_ID = DINGTALK_CLIENT_ID
    DINGTALK_CLIENT_SECRET = DINGTALK_CLIENT_SECRET
    API_KEY = API_KEY
    MODEL_KEY = MODEL_KEY
    WORK_DIR = WORK_DIR
    SANDBOX_DIR = SANDBOX_DIR
    SCRIPT_DIR = SCRIPT_DIR
    TIMEOUT = TIMEOUT
    HTTP_PROXY = HTTP_PROXY
    HTTPS_PROXY = HTTPS_PROXY
    GITHUB_REPO = GITHUB_REPO
    FORBIDDEN_PATTERNS = FORBIDDEN_PATTERNS
    ALLOWED_COMMANDS = []  # 废弃，使用黑名单模式
    MODELS = MODELS
    MODELS = MODELS

    @staticmethod
    def get_model_id():
        return get_model_id()
