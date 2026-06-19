# My Agent — 多模态 Agent 管理与桌面自动化工具集

> **相关文档**
> - [Agent 管理脚本使用指南](AGENTS.md) — Master-Slave 架构的 Agent 管理
> - [Chrome 浏览器控制](chrome.md) — Lua + xdotool 的 Chrome 控制 API
> - [WeChat OCR 技术文档](wechat-ocr/WECHAT_OCR.md) — 桌面微信 OCR 识别与自动化
> - [WeChat OCR 快速入门](wechat-ocr/README.md) — 微信自动化 Lua API 使用指南
> - [UTEL 编码规则](rule.md) — LLM 文本压缩编码协议

---

## 项目概述

本项目是一个面向 Linux 桌面的**多模态 Agent 管理系统与自动化工具集**，围绕以下核心能力构建：

- **Agent 管理** — 基于 OpenCode + tmux 的 Master-Slave 架构，支持创建、管理、监控多个 Agent 实例
- **微信自动化** — 通过 LuaJIT + C++ + ONNX Runtime GPU 实现桌面微信的识别、操作与监控
- **图像生成** — 基于 stable-diffusion.cpp 的本地 GPU 图像生成
- **多模态 C 封装** — SenseVoice (ASR) 和 JoyCaption (Vision) 的 C 语言绑定
- **Chrome 控制** — 纯 Lua 实现的 Chrome 浏览器操作（不需 MCP 守护进程）
- **UTEL 编码** — 针对 LLM 的文本压缩编码协议，含 Python 编码器实现

---

## 目录结构

```
my-agent/
├── README.md                          # 本文档
├── AGENTS.md                          # Agent Master-Slave 架构指南
├── agent.sh                           # Agent 管理脚本（启动/停止/发送指令）
├── start.sh                           # 一键启动脚本（当前依赖已删除的 ding/ 目录）
├── img.sh                             # 本地图像生成脚本（stable-diffusion.cpp）
├── chrome.md                          # Chrome 浏览器控制模块文档
├── rule.md                            # UTEL 编码规则完整文档
├── utel_encoder.py                    # UTEL 编码器 Python 实现
│
├── wechat-ocr/                        # 桌面微信自动化框架
│   ├── wechat_robot.lua              # 统一 Lua API 库
│   ├── run.lua                       # 入口脚本
│   ├── lib/                          # C++ 动态库 + API
│   ├── src/                          # 截图、OCR 推理 C++ 源码
│   ├── lua/                          # Lua 辅助模块
│   ├── tests/                        # 测试脚本
│   ├── models/                       # OCR 模型文件
│   ├── build_final.sh                # C 库构建脚本
│   └── CMakeLists.txt                # CMake 构建配置
│
├── sense-voice-wrapper/               # SenseVoice ASR C 封装源码备份
│   └── sensevoice_wrapper.cpp
│
├── joycaption-wrapper/                # JoyCaption Vision C 封装源码备份
│   └── joycaption_wrapper.cpp
│
├── models/                            # OCR 模型文件（PP-OCRv4）
│   ├── ch_PP-OCRv4_det_infer.onnx
│   ├── ch_PP-OCRv4_rec_infer.onnx
│   └── ppocr_keys_v1.txt
│
└── .gitignore
```

---

## 模块详解

### 1. Agent 管理 — Master-Slave 架构

基于 OpenCode 和 tmux 的 Agent 管理方案。

| 角色 | 名称 | 端口 | 职责 |
|------|------|------|------|
| **Master** | master | 4097 | 任务分配、Slave 管理、状态监控 |
| **Slave** | coder, reviewer... | 4098+ | 接收任务、执行工作、汇报结果 |

**快速开始：**

```bash
# 启动 Master
./agent.sh start master

# 启动 Slave
./agent.sh start coder

# 发送任务
./agent.sh send coder "写一个 Python 爬虫"

# 查看状态
./agent.sh status

# 附加到 tmux 查看执行过程
./agent.sh attach coder
```

**心跳机制：**
- Master 每 25 分钟自心跳，防止无故停机
- Slave 每 15 分钟向 Master 汇报状态
- 连续 3 次健康检查失败自动重启 Agent

详见 [AGENTS.md](AGENTS.md)。

---

### 2. 微信自动化 — WeChat OCR

基于 LuaJIT + C++ + ONNX Runtime GPU 的桌面微信操作框架。

**核心能力：**

| 功能 | 说明 |
|------|------|
| 窗口定位 | 白面板检测 + 跨桌面切换 + xdotool 兜底 |
| 聊天文字识别 | PaddleOCR PP-OCRv4，GPU 加速 |
| 逐字输入发送 | 剪贴板 + 随机延时 + 回车 |
| 文件/截图发送 | 模拟点击图标 + 粘贴路径 |
| 联系人搜索 | 搜索框 + 通讯录双路径 |
| 持续监控 | 轮询检测新消息，回调通知 |
| Chrome AI 搜索 | 微信指令 → Chrome AI 搜索 → 结果回微信 |
| 操作录屏 | ffmpeg 录制完整操作过程 |

**快速使用：**

```lua
local robot = require("wechat_robot")
robot.init()
robot.search("小王")
robot.send("你好！")
local text = robot.capture()
robot.destroy()
```

详见 [wechat-ocr/README.md](wechat-ocr/README.md) 和 [WECHAT_OCR.md](wechat-ocr/WECHAT_OCR.md)。

---

### 3. 图像生成 — stable-diffusion.cpp

本地 GPU 图像生成脚本，基于 `stable-diffusion.cpp`。

```bash
# 基本用法
./img.sh "A beautiful landscape"

# 自定义尺寸
./img.sh "A sunset" /path/to/output.png 1280 720

# 环境变量覆盖参数
SAMPLING_METHOD=euler CFG_SCALE=3.2 STEPS=25 ./img.sh "..."
```

| 特性 | 说明 |
|------|------|
| 模型 | SD Turbo (Q5_K_M) |
| VAE | ae.safetensors |
| 增强 | FreeU + SAG + Auto-enhance |
| GPU | RTX 3080 |

---

### 4. Chrome 浏览器控制

纯 Lua 实现，通过 xdotool 模拟键盘快捷键操作现有 Chrome 窗口（不打开新浏览器）。

```lua
local chrome = require("wechat_ocr.chrome")
chrome.new_tab()              -- Ctrl+T 新标签
chrome.open("网址")            -- 新标签打开网址
chrome.search("关键词")        -- Google 搜索
chrome.ai_search("问题")       -- AI 模式搜索
chrome.screenshot()            -- 截图
```

详见 [chrome.md](chrome.md)。

---

### 5. 多模态 C 封装

| 模块 | 功能 | 技术方案 |
|------|------|---------|
| **SenseVoice** | 语音转文本 (ASR) | C++ wrapper → `libsensevoice.so` |
| **JoyCaption** | 图片分析 (Vision) | C++ wrapper → `libjoycaption.so` |

源码备份存放在：
- `sense-voice-wrapper/sensevoice_wrapper.cpp`
- `joycaption-wrapper/joycaption_wrapper.cpp`

---

### 6. UTEL 编码系统

针对 LLM 的文本压缩编码协议，支持自然语言和代码的双模式压缩。

```python
from utel_encoder import UTEL_Encoder

encoder = UTEL_Encoder()
compressed = encoder.pack("请帮我实现一个红黑树，需要支持完整的插入、删除操作。")
```

**特性：**
- 自然语言：双拼音节编码 + 逻辑符号
- 代码：`#code ... #end` 块内 1:1 脱水/还原
- 多版本演进 (v2.1 ~ v3.2)

详见 [rule.md](rule.md) 和 `utel_encoder.py`。

---

## 构建与运行

### 微信 OCR 模块

```bash
cd wechat-ocr
cmake -S . -B build_lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib/cmake"
cmake --build build_lib -j$(nproc) --target wechat_ocr_core
```

### Agent 管理

```bash
# 确保已安装依赖
# tmux, opencode

# 启动 Master
./agent.sh start master

# 启动 Worker
./agent.sh start coder
```

### 图像生成

```bash
# 需要 stable-diffusion.cpp 编译的 myimg-cli
# 模型文件位于 /opt/image/model/
./img.sh "prompt"
```

---

## 依赖汇总

| 组件 | 用途 | 所属模块 |
|------|------|---------|
| OpenCode + tmux | Agent 管理与运行 | Agent 管理 |
| LuaJIT | 微信自动化脚本语言 | WeChat OCR |
| ONNX Runtime GPU | 深度学习推理 | WeChat OCR |
| PaddleOCR PP-OCRv4 | 文字检测+识别模型 | WeChat OCR |
| OpenCV | 图像处理 | WeChat OCR |
| xdotool / xclip | 桌面操作 | WeChat OCR / Chrome |
| ffmpeg | 录屏 | WeChat OCR |
| CUDA | GPU 加速 | WeChat OCR |
| stable-diffusion.cpp | 本地图像生成 | Image Gen |
| SenseVoice.cpp | 语音识别 ASR | C Wrappers |

---

## 注意事项

1. **start.sh 需更新** — 当前引用了已删除的 `ding/` 目录，需根据实际需求调整
2. **模型文件** — 大模型文件通过 `.gitignore` 排除，部署时需手动下载
3. **Agent 心跳** — Slave 每 15 分钟收到系统自动心跳消息，Slave 应忽略这些消息无需回复
4. **微信安全** — 微信自动化操作频率不宜过高，避免触发风控

---

*文档版本: 2.0*
*更新日期: 2026-06-19*
