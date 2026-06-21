# My Agent — 微信机器人远程入口与自动化执行框架

> **核心定位**：把微信（客户端已替换为「小龙虾」）作为远程消息入口，通过 OCR 识别聊天内容，将消息解析为指令并执行，再把结果回发到微信。无需额外安装微信客户端。
>
> **相关文档**
> - [Agent 管理脚本使用指南](AGENTS.md) — Master-Slave 架构的 Agent 管理
> - [WeChat 机器人快速入门](wechat-ocr/README.md) — 微信自动化 Lua API 与指令执行流程
> - [WeChat OCR 技术文档](wechat-ocr/WECHAT_OCR.md) — 截图、OCR、窗口定位实现细节
> - [Chrome 浏览器控制](chrome.md) — Lua + xdotool 的 Chrome 控制 API
> - [UTEL 编码规则](rule.md) — LLM 文本压缩编码协议

---

## 项目概述

本项目运行在 Linux 桌面环境上，核心目标是把**微信变成一个远程控制入口**：

1. 用户通过手机或其他微信客户端，给运行本项目的微信号发消息；
2. 项目持续监控微信聊天窗口，用 OCR 识别新消息内容；
3. 识别出的文本被解析为指令（系统命令、Agent 任务、Chrome 搜索、文件操作等）；
4. 执行指令并将结果发送回微信。

**微信客户端已被替换为「小龙虾」**，本项目可以直接与其交互，不需要额外安装官方微信。

---

## 核心工作流

```
手机/远程微信
      │ 发送消息
      ▼
┌─────────────────┐
│  小龙虾（桌面微信） │
└─────────────────┘
      │ 聊天窗口显示消息
      ▼
┌─────────────────┐     ┌─────────────┐
│ 截图 + OCR 识别  │────▶│ 文本指令解析 │
└─────────────────┘     └─────────────┘
                              │
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
      ┌───────────┐    ┌──────────┐    ┌──────────────┐
      │ 执行系统命令 │    │ Chrome搜索 │    │ 转发给 Agent │
      └───────────┘    └──────────┘    └──────────────┘
            │                 │                 │
            └─────────────────┴─────────────────┘
                              ▼
                       ┌─────────────┐
                       │ 结果回发微信  │
                       └─────────────┘
```

---

## 目录结构

```
my-agent/
├── README.md                          # 本文档
├── AGENTS.md                          # Agent Master-Slave 架构指南
├── agent.sh                           # Agent 管理脚本（启动/停止/发送指令）
├── chrome.md                          # Chrome 浏览器控制模块文档
├── rule.md                            # UTEL 编码规则完整文档
├── utel_encoder.py                    # UTEL 编码器 Python 实现
│
├── wechat-ocr/                        # 微信机器人核心框架
│   ├── wechat_robot.lua              # 统一 Lua API 库（消息收发、搜索、监控）
│   ├── run.lua                       # 入口脚本
│   ├── run_ops.lua                   # 演示脚本：打开 → 发送 → 验证
│   ├── lib/                          # C++ 动态库 + C API
│   ├── src/                          # 截图、OCR 推理 C++ 源码
│   ├── lua/                          # Lua 辅助模块（FFI 绑定、监控循环）
│   ├── tests/                        # 测试脚本
│   ├── models/                       # OCR 模型文件
│   ├── build_final.sh                # C 库构建脚本
│   ├── run.sh                        # 启动环境脚本
│   └── CMakeLists.txt                # CMake 构建配置
│
├── sense-voice-wrapper/               # SenseVoice ASR C 封装源码（备用）
│   └── sensevoice_wrapper.cpp
│
├── joycaption-wrapper/                # JoyCaption Vision C 封装源码（备用）
│   └── joycaption_wrapper.cpp
│
└── .gitignore
```

> 注：历史遗留的 `start.sh`（引用已删除的 ding/ 目录）和 `img.sh`（图像生成脚本）不再作为项目主线维护。

---

## 模块详解

### 1. 微信机器人入口 — WeChat OCR

基于 LuaJIT + C++ + ONNX Runtime GPU 实现。

**核心能力：**

| 功能 | 说明 |
|------|------|
| 窗口定位 | 白面板检测 + 跨桌面切换 + xdotool 兜底 |
| 聊天文字识别 | PaddleOCR PP-OCRv4，GPU 加速 |
| 指令消息捕获 | 监控第三列聊天内容，提取用户指令 |
| 结果回发 | 剪贴板粘贴 + 回车发送 |
| 联系人搜索 | 搜索框 + 通讯录双路径 |
| 文件/截图发送 | 模拟点击图标 + 粘贴路径 |
| 持续监控 | `monitor()` 轮询检测新消息，回调通知 |
| Chrome AI 搜索 | 微信指令 → Chrome AI 搜索 → 结果回微信 |
| 操作录屏 | ffmpeg 录制完整操作过程 |

**快速使用：**

```lua
local robot = require("wechat_robot")
robot.init()
robot.search("小王")
robot.send("你好！")
local text = robot.capture()   -- 读取聊天内容（即用户发来的指令）
robot.destroy()
```

详见 [wechat-ocr/README.md](wechat-ocr/README.md) 和 [WECHAT_OCR.md](wechat-ocr/WECHAT_OCR.md)。

---

### 2. Agent 管理 — Master-Slave 架构

基于 OpenCode 和 tmux 的 Agent 管理方案，用于把复杂指令分发给不同 Slave Agent 执行。

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
```

**心跳机制：**
- Master 每 25 分钟自心跳，防止无故停机
- Slave 每 15 分钟向 Master 汇报状态
- 连续 3 次健康检查失败自动重启 Agent

详见 [AGENTS.md](AGENTS.md)。

---

### 3. Chrome 浏览器控制

纯 Lua 实现，通过 xdotool 模拟键盘快捷键操作现有 Chrome 窗口（不打开新浏览器）。

```lua
local chrome = require("wechat_ocr.chrome")
chrome.new_tab()              -- Ctrl+T 新标签
chrome.open("网址")            -- 新标签打开网址
chrome.search("关键词")        -- Google 搜索
chrome.ai_search("问题")       -- AI 模式搜索
chrome.screenshot()           -- 截图
```

详见 [chrome.md](chrome.md)。

---

### 4. 多模态 C 封装（备用）

| 模块 | 功能 | 技术方案 |
|------|------|---------|
| **SenseVoice** | 语音转文本 (ASR) | C++ wrapper → `libsensevoice.so` |
| **JoyCaption** | 图片分析 (Vision) | C++ wrapper → `libjoycaption.so` |

源码备份：
- `sense-voice-wrapper/sensevoice_wrapper.cpp`
- `joycaption-wrapper/joycaption_wrapper.cpp`

---

### 5. UTEL 编码系统

针对 LLM 的文本压缩编码协议，支持自然语言和代码的双模式压缩，可用于在 Agent 之间高效传输长文本。

```python
from utel_encoder import UTEL_Encoder

encoder = UTEL_Encoder()
compressed = encoder.pack("请帮我实现一个红黑树，需要支持完整的插入、删除操作。")
```

详见 [rule.md](rule.md) 和 `utel_encoder.py`。

---

## 构建与运行

### 微信机器人核心库

```bash
cd wechat-ocr
cmake -S . -B build_lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib/cmake"
cmake --build build_lib -j$(nproc) --target wechat_ocr_core
```

### 运行微信机器人

```bash
cd wechat-ocr
./run.sh
```

或手动设置环境变量后运行：

```bash
export LD_LIBRARY_PATH="./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib"
export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/usr/local/lualib/?.so;;"
luajit run.lua
```

### Agent 管理

```bash
# 启动 Master
./agent.sh start master

# 启动 Worker
./agent.sh start coder
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
| 小龙虾（微信客户端） | 远程消息入口 | WeChat OCR |

---

## 注意事项

1. **小龙虾即微信客户端**：本项目直接操作桌面上的「小龙虾」窗口，不需要额外安装官方微信。
2. **Agent 心跳**：Slave 每 15 分钟收到系统自动心跳消息，Slave 应忽略这些消息无需回复。
3. **操作频率**：微信自动化操作频率不宜过高，避免触发风控。
4. **OCR 依赖**：模型文件较大，通过 `.gitignore` 排除，部署时需确保 `wechat-ocr/models/` 下有 ONNX 模型。
5. **Chrome 控制规则**：只能用 Lua 调用、只能操作现有 Chrome 窗口、禁止用 OCR 识别浏览器页面，详见 [chrome.md](chrome.md) 和 [wechat-ocr/CLAUDE.md](wechat-ocr/CLAUDE.md)。

---

*文档版本: 3.0*
*更新日期: 2026-06-21*
