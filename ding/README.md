## 插件开发指南

### 新插件实现流程（3 步）

**系统采用动态自动发现机制，无需 JSON 注册，无需修改核心代码。**

#### 第 1 步：创建任务文件

在 `tasks/` 目录下创建新文件，文件名即指令名。

例如创建 `tasks/img.py` → 用户发送 `#img` 即可触发

#### 第 2 步：实现任务类

```python
from tasks.base import BaseTask, TaskResult

class ImgTask(BaseTask):
    task_type = "img"  # 指令名，必须与文件名一致
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        # 获取用户原始输入
        raw = content.get("raw", "")
        # 去掉 #img 前缀，提取参数
        args = raw.replace("#img", "").strip()
        
        # 执行业务逻辑...
        
        # 返回结果
        return TaskResult.ok("执行成功").to_dict()
```

**关键要求：**
- 必须继承 `BaseTask`
- 必须定义 `task_type`（与文件名一致）
- 必须实现 `execute(content, session_webhook)` 方法
- 返回 `dict` 格式：`{"success": bool, "stdout": str, "stderr": str, "error": str}`

#### 第 3 步：重启 Worker

```bash
# 停止旧 Worker
pkill -f task_worker.py

# 启动新 Worker（自动扫描并注册新任务）
setsid python3 task_worker.py >> worker.log 2>&1 < /dev/null &
```

Worker 启动时会自动扫描 `tasks/` 目录，所有继承 `BaseTask` 的类都会被自动注册。

---

### 完整参考案例：#img 指令实现

**文件：** `tasks/img.py`

**功能：** 接收提示词，调用本地 `img.sh` 生成图片，上传到钉钉并发送给用户。

```python
"""
图像生成任务 - 调用本地 stable-diffusion.cpp 生成图片
用法:
    #img 一只可爱的猫坐在窗台上
    #img 夕阳下的海边 1280 720
"""
import sys
import os
import subprocess
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult
from logger import task_logger as logger
import dingtalk

IMG_SH = "/home/dministrator/my-agent/img.sh"
OUTPUT_DIR = os.path.expanduser("~")


class ImgTask(BaseTask):
    """本地图像生成任务"""
    task_type = "img"
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        raw = content.get("raw", "")
        args_str = raw.replace("#img", "").strip()
        
        if not args_str:
            return TaskResult.err("请提供提示词，例如: #img 一只可爱的猫").to_dict()
        
        # 解析参数：提示词 [宽度] [高度]
        parts = args_str.split()
        width = "1280"
        height = "720"
        prompt = args_str
        
        # 从后往前检查，最后两个纯数字作为宽高
        if len(parts) >= 3 and parts[-1].isdigit() and parts[-2].isdigit():
            height = parts[-1]
            width = parts[-2]
            prompt = " ".join(parts[:-2])
        
        # 生成输出文件路径
        timestamp = str(int(time.time()))
        output_file = os.path.join(OUTPUT_DIR, f"img_{timestamp}.png")
        
        # 调用 img.sh 生成图片
        cmd = [IMG_SH, prompt, output_file, width, height]
        logger.info(f"[ImgTask] 生成图片: {prompt}, {width}x{height}")
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        
        if result.returncode != 0:
            return TaskResult.err(f"生成失败: {result.stderr[:500]}").to_dict()
        
        # 上传并发送图片
        exec_responses = ""
        if session_webhook and os.path.exists(output_file):
            dt = dingtalk.get_dingtalk()
            with open(output_file, "rb") as f:
                media_id = dt.upload_media("image", file_content=f.read())
            if media_id:
                dt.send_image(session_webhook, media_id)
                exec_responses = f"__MEDIA_ID__: {media_id}"
        
        return TaskResult(
            success=True,
            stdout=f"图片生成成功: {output_file}",
            exec_responses=exec_responses
        ).to_dict()
```

**关键点：**
1. `task_type = "img"` → 用户发送 `#img` 触发
2. 解析 `content["raw"]` 提取提示词和参数
3. 使用 `subprocess.run()` 调用外部脚本
4. 通过 `dingtalk.upload_media()` + `send_image()` 发送图片
5. 在 `exec_responses` 中返回 `__MEDIA_ID__`，主进程检测到后不再发送文本

---

### 插件可用资源

```python
# 执行 Shell 命令（带安全黑名单）
from executor import Executor
e = Executor()
result = e.execute("ls -la")

# 执行 Python 代码（沙盒隔离）
result = e.execute_python_subprocess("print('hello')")

# 调用远程 AI
from ai import AI
ai = AI()
result = ai.analyze("问题")

# 钉钉 API（发送消息/上传图片）
import dingtalk
dt = dingtalk.get_dingtalk()
dt.send_text(session_webhook, "消息内容")
dt.send_image(session_webhook, media_id)

# HTTP 请求
import requests
resp = requests.get("https://api.example.com")
```

---

## 目录结构

```
ding/
├── autobot_dingtalk.py      # 主进程：消息接收 + 任务分发
├── task_worker.py           # Worker 进程：任务执行
├── executor.py              # 执行器：Shell/Python 安全执行
├── ai.py                    # AI 模块：任务分析 + 图片分析
├── siliconflow.py           # SiliconFlow API 完整封装
├── dingtalk.py              # 钉钉 API：Token/媒体/消息
├── config.py                # 配置管理：模型列表 + 安全黑名单
├── prompt.py                # 系统提示词管理
├── guardian.py              # 守护进程：进程监控 + 自动重启
├── logger.py                # 日志模块：彩色控制台 + 文件
├── nano_banana.py           # 图像生成模块
├── test_*.py                # 测试脚本
├── tasks/                   # 插件目录（自动扫描）
│   ├── __init__.py
│   ├── base.py              # BaseTask 基类 + TaskResult
│   ├── registry.py          # TaskRegistry 注册表（自动加载）
│   ├── shell.py             # #shell 指令
│   ├── code.py              # #code 指令
│   ├── python.py            # #python 指令
│   ├── weather.py           # #weather 指令
│   ├── img.py               # #img 指令（本地生成图片）
│   ├── ai_image.py          # 默认 AI 对话
│   ├── ai_analyze.py        # 图片分析
│   ├── opencode.py          # #opencode 指令
│   ├── write.py             # #write 指令
│   └── test.py              # #test 指令
├── logs/                    # 日志目录
│   ├── ai.log
│   ├── task.log
│   ├── executor.log
│   └── ...
└── run.log                  # 主进程日志
```

**重要：** `tasks/` 目录下的所有 `.py` 文件（除 `base.py`、`registry.py`、`_` 开头外）都会被自动扫描并注册，**无需手动添加配置**。