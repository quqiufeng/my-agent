# Agent 管理系统 - 架构设计文档

## 1. 项目概述

本项目是一个基于钉钉的 **多 Agent 统一入口系统**。用户通过手机钉钉（支持语音输入）发送指令，系统通过 Master Agent 管理和调度多个 Worker Agent 执行复杂任务，实现"口袋里的远程编程助手"。

**核心场景**：手机钉钉 → 语音输入 → 远程写代码/管理服务器/执行复杂任务

---

## 2. 系统架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────┐
│                        用户端                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │ 钉钉手机 │  │ 钉钉PC   │  │ 语音输入 │                  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                  │
│       └──────────────┴──────────────┘                      │
│                         │                                  │
│                    WebSocket Stream                        │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│                    钉钉网关层                                │
│              ┌─────────────────────┐                       │
│              │  autobot_dingtalk   │  接收消息、解析指令     │
│              │     (主进程)        │  文件中转、结果回传     │
│              └──────────┬──────────┘                       │
└─────────────────────────┼───────────────────────────────────┘
                          │ 消息/任务
┌─────────────────────────▼───────────────────────────────────┐
│                    核心调度层                                │
│              ┌─────────────────────┐                       │
│              │    task_worker      │  任务分发、插件执行     │
│              │    (Worker进程)     │  结果收集、错误处理     │
│              └──────────┬──────────┘                       │
└─────────────────────────┼───────────────────────────────────┘
                          │
              ┌───────────┼───────────┐
              │           │           │
     ┌────────▼───┐ ┌─────▼────┐ ┌───▼────┐
     │   本地插件  │ │ 本地执行  │ │ Agent  │
     │  tasks/*.py │ │ executor │ │ 调度   │
     └─────────────┘ └──────────┘ └───┬────┘
                                      │
┌─────────────────────────────────────▼───────────────────────┐
│                    Agent 管理层                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Master Agent (中央控制器)                │   │
│  │  tmux session: master  port: 4097                   │   │
│  │  - Agent 生命周期管理（创建/停止/监控）               │   │
│  │  - 指令路由与分发                                     │   │
│  │  - 状态聚合与汇报                                     │   │
│  └──────────────────────┬──────────────────────────────┘   │
│                         │ HTTP API                         │
│         ┌───────────────┼───────────────┐                  │
│         │               │               │                  │
│  ┌──────▼─────┐  ┌─────▼──────┐  ┌─────▼──────┐          │
│  │ Worker-1   │  │ Worker-2   │  │ Worker-N   │          │
│  │ 代码专家   │  │ 系统运维   │  │ 数据分析   │          │
│  │ port:4098  │  │ port:4099  │  │ port:4100  │          │
│  └────────────┘  └────────────┘  └────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 进程架构

| 进程 | 职责 | 特点 |
|------|------|------|
| **主进程** (autobot_dingtalk) | 接收钉钉消息、维持长连接、文件下载 | 永不崩溃，轻量级 |
| **Worker进程** (task_worker) | 执行插件任务、管理本地资源 | 可重启，不影响主进程 |
| **Master Agent** (tmux:master) | Agent 管理中枢、指令路由 | 常驻，自动恢复 |
| **Worker Agent** (tmux:agent-*) | 具体任务执行、代码编写 | 动态创建，独立环境 |

### 2.3 数据流

```
用户消息 → 钉钉 → 主进程 → Worker进程 → Agent插件
                                              ↓
                         结果 ← 主进程 ← Master Agent ← Worker Agent
```

### 2.4 指令执行流程

系统支持两种指令类型：**#标签指令** 和 **自然语言指令**

#### A. #标签指令执行流程

用户发送以 `#` 开头的指令，如 `#img 一只猫`、`#shell ls -la`

```
用户: #img 一只可爱的猫
  ↓
autobot_dingtalk.py:182  正则匹配 #(\w+) → directive_name="img"
  ↓
autobot_dingtalk.py:186  检查 tasks/img.py 是否存在
  ↓
autobot_dingtalk.py:189  dispatch_task("img", {"raw": "#img 一只可爱的猫"})
  ↓
TaskClient 通过 Unix Domain Socket 发送任务
  ↓
task_worker.py (TaskServer) 实时接收任务
  ↓
do_task() → get_task("img") → ImgTask()
  ↓
tasks/img.py:85          execute()
  ├─ 解析参数: prompt="一只可爱的猫"
  ├─ 调用 img.sh (RTX 3080) 生成图片
  ├─ 上传钉钉: dt.upload_media()
  └─ 发送图片: dt.send_markdown_image()
    ↓
返回 TaskResult(exec_responses="__MEDIA_ID__: xxx")
  ↓
TaskServer 通过 Socket 返回结果
  ↓
TaskClient 收到结果
  ↓
autobot_dingtalk.py:234  检测到 __MEDIA_ID__
  ↓
不发送文本（图片已发送）
  ↓
返回 AckMessage.STATUS_OK
```

#### B. 自然语言指令执行流程

用户发送自然语言，如 "生成一张喵咪图片"、"帮我写个爬虫"

```
用户: 生成一张喵咪图片
  ↓
autobot_dingtalk.py:243  检测无 #标签 → 走 ai_image 任务
  ↓
autobot_dingtalk.py:244  dispatch_task("ai_image", {"user_input": "生成一张喵咪图片"})
  ↓
TaskClient 通过 Unix Domain Socket 发送任务
  ↓
task_worker.py (TaskServer) 实时接收任务
  ↓
do_task() → get_task("ai_image") → AIImageTask()
  ↓
tasks/ai_image.py:67     _handle_text()
  ├─ ai.analyze("生成一张喵咪图片") → 调用本地 OpenCode API
  │     ↓
  │   prompt.py:24        system prompt 意图识别规则
  │   "如果用户消息是生成图片...返回 #img 指令"
  │     ↓
  │   OpenCode 返回: "#img a cute fluffy cat, big eyes..."
  │     ↓
  ├─ ai_image.py:72      正则匹配 #img → 提取提示词
  │     ↓
  ├─ ai_image.py:86      调用 ImgTask.execute({"raw": "#img ..."})
  │     ↓
  │   （进入 A 流程，从 ImgTask 开始执行）
  │     ↓
  └─ 返回 TaskResult(exec_responses="__MEDIA_ID__: xxx")
    ↓
TaskServer 通过 Socket 返回结果
  ↓
TaskClient 收到结果
  ↓
autobot_dingtalk.py:266  检测到 __MEDIA_ID__
  ↓
不发送文本（图片已发送）
  ↓
返回 AckMessage.STATUS_OK
```

**关键区别：**

| 类型 | 触发方式 | 意图识别 | 执行路径 |
|------|---------|---------|---------|
| **#标签指令** | 用户直接发送 `#xxx` | 主进程正则匹配 | 直接分发到对应任务 |
| **自然语言指令** | 用户发送普通文本 | OpenCode AI 分析意图 | 先走 ai_image 意图识别，再分发 |

**通信机制（Unix Domain Socket）：**

| 维度 | 文件轮询（旧） | Socket 通信（新） |
|------|---------------|------------------|
| **延迟** | 0.5-1s 轮询等待 | 实时通信，无延迟 |
| **可靠性** | 文件读写可能冲突 | Socket 内核处理，更可靠 |
| **超时控制** | 固定 sleep 检查 | 支持 socket 级别超时 |
| **Worker 断开** | 任务文件堆积 | 连接断开立即感知 |
| **重连能力** | 无 | 支持自动重连 |

**支持的 #标签：**

| 标签 | 功能 | 典型场景 |
|------|------|---------|
| `#agent` | 智能任务执行 | 写代码、创建插件、复杂任务 |
| `#img` | 本地图片生成 | 画画、生成图片、做图 |
| `#shell` | 执行 Shell 命令 | 查看文件、系统操作 |
| `#code` / `#python` | 执行 Python 代码 | 计算、测试代码 |
| `#ai_analyze` | AI 分析媒体 | 图片分析、语音转写（自动触发） |
| `#test` | 测试任务 | 测试系统功能 |
| `#write` | 写入文件 | 保存代码到文件 |

---

## 3. 核心概念

### 3.1 Agent 定义

Agent 是一个**独立的 OpenCode 实例**，运行在独立的 tmux session 中，通过 HTTP API 接受指令并执行。

每个 Agent 具有：
- **唯一标识**：如 `master`, `coder`, `ops`, `data`
- **独立端口**：如 4097, 4098, 4099...
- **独立工作目录**：如 `~/agents/coder/`
- **独立上下文**：记忆、历史、环境变量

### 3.2 Master Agent

Master 是特殊的 Agent，职责：
1. **注册中心**：维护所有 Agent 的清单和状态
2. **路由网关**：根据指令内容分发给合适的 Worker Agent
3. **生命周期管理**：创建、停止、重启 Worker Agent
4. **状态监控**：心跳检测、日志聚合、异常恢复

### 3.3 指令格式

```
#agent <agent_name> <指令内容>
```

示例：
- `#agent master 创建一个叫 coder 的 Agent，专门写 Python`
- `#agent coder 帮我写一个爬取豆瓣电影的脚本`
- `#agent ops 查看服务器内存使用情况`
- `#agent master 列出所有 Agent 状态`

---

## 4. 模块设计

### 4.1 钉钉网关 (autobot_dingtalk.py)

**职责**：与钉钉保持 WebSocket 长连接，接收所有消息类型

**支持的输入**：
- 文本消息（含 #指令）
- 图片消息（自动分析）
- 文件消息（自动下载分析）
- 语音消息（自动语音识别）
- Markdown 消息

**输出处理**：
- 文本回复（截断 1000 字符）
- 图片发送（通过 media_id）
- 文件发送（通过钉钉文件接口）
- 语音转文字后处理

### 4.2 任务调度 (task_worker.py)

**职责**：插件加载、任务执行、结果收集

**插件机制**：
- 自动扫描 `tasks/` 目录
- 继承 `BaseTask` 即可注册
- 支持热加载（重启 Worker 生效）

**执行模式**：
- 同步执行：简单任务（如天气查询）
- 异步委托：复杂任务（如 Agent 指令）转交 Master 处理

### 4.3 Agent 管理 (tasks/agent.py)

**核心功能**：

```python
class AgentTask(BaseTask):
    task_type = "agent"
    
    def execute(self, content, session_webhook):
        # 1. 解析指令
        # 2. 路由到目标 Agent
        # 3. 调用 Master 或直接执行
        # 4. 返回结果
```

**子功能**：

| 功能 | 说明 | 示例 |
|------|------|------|
| `create` | 创建新 Agent | `#agent master create coder` |
| `destroy` | 销毁 Agent | `#agent master destroy coder` |
| `list` | 列出所有 Agent | `#agent master list` |
| `status` | 查看 Agent 状态 | `#agent master status coder` |
| `send` | 发送指令给 Agent | `#agent coder 写个脚本` |
| `broadcast` | 广播指令 | `#agent master broadcast 全部更新` |

### 4.4 Master Agent 服务 (master.py)

**启动流程**：

```bash
# 1. 启动 Master OpenCode Server
tmux new-session -d -s master "opencode serve --port 4097 --work-dir ~/agents/master"

# 2. 启动 Master Agent TUI
tmux new-window -t master -n tui "opencode attach http://localhost:4097"

# 3. 启动 Master 管理脚本（监听 HTTP 或共享文件）
tmux new-window -t master -n daemon "python master_daemon.py"
```

**master_daemon.py 职责**：
- 维护 `~/agents/registry.json`（Agent 注册表）
- 提供 HTTP API：
  - `POST /agent/create` - 创建 Agent
  - `POST /agent/destroy` - 销毁 Agent
  - `GET /agent/list` - 列出 Agent
  - `GET /agent/status/<name>` - 查看状态
  - `POST /agent/<name>/send` - 发送指令
- 心跳检测：定期检查 Agent 健康状态
- 自动恢复：崩溃的 Agent 自动重启

### 4.5 Worker Agent

**创建流程**：

```bash
# Master 收到创建请求后执行：

# 1. 创建工作目录
mkdir -p ~/agents/coder

# 2. 生成配置文件
cat > ~/agents/coder/config.json << EOF
{
  "name": "coder",
  "port": 4098,
  "work_dir": "~/agents/coder",
  "system_prompt": "你是一个专业的 Python 程序员...",
  "created_by": "master",
  "created_at": "2024-01-01T00:00:00"
}
EOF

# 3. 启动 tmux session
tmux new-session -d -s agent-coder "opencode serve --port 4098 --work-dir ~/agents/coder"

# 4. 注册到 Master
# 写入 registry.json
```

**特点**：
- 每个 Worker 是独立的 OpenCode 实例
- 有自己的工作目录和上下文
- 通过 HTTP API 接受指令
- 可独立重启，不影响其他 Agent

---

## 5. 语音功能集成

系统支持**语音转文本（ASR）**和**文本转语音（TTS）**功能，基于 SenseVoice 和 Piper 两个开源项目源码集成。

### 5.1 模型文件位置

所有模型文件存放在**源码目录下的 `models/` 中**，不放入项目目录，保持项目轻量：

| 功能 | 模型路径 | 大小 |
|------|---------|------|
| **ASR (SenseVoice)** | `/home/dministrator/SenseVoice.cpp/models/sense-voice-small-q6_k.gguf` | ~230MB |
| **TTS (Piper)** | `/opt/piper-src/models/zh_CN-huayan-medium.onnx` | ~63MB |

> 注意：模型文件通过 `.gitignore` 排除，不会提交到 git。部署新机器时需手动下载或复制。

### 5.2 新增代码文件

以下文件为本次集成新增/修改，已备份到项目目录：

| 文件 | 说明 | 位置 |
|------|------|------|
| `ding/voice_recognition.py` | ASR Python 封装（ctypes） | 项目目录 |
| `ding/text_to_speech.py` | TTS Python 封装（ctypes） | 项目目录 |
| `sense-voice-wrapper/sensevoice_wrapper.cpp` | SenseVoice C wrapper | 项目目录（备份） |
| `libs/libsensevoice.so` | SenseVoice 共享库 | 项目目录（编译产物） |
| `src/cpp/piper_wrapper.cpp` | Piper C wrapper | `/opt/piper-src/src/cpp/` |
| `libpiper_tts.so` | Piper 共享库 | `/opt/piper-src/build/` |

### 5.3 语音转文本（ASR）- SenseVoice

#### 架构

```
用户语音消息 → voice_recognition.py → ctypes → libsensevoice.so → SenseVoice C++ API → 文本
```

**特点**：
- 模型**常驻内存**，首次加载后复用
- 支持 GPU 加速（CUDA）
- 支持多种音频格式（自动转换为 WAV）

#### 编译方法

在 SenseVoice.cpp 源码目录执行：

```bash
cd /home/dministrator/SenseVoice.cpp

# 1. 重新编译静态库（添加 -fPIC）
mkdir -p build && cd build
cmake -DCMAKE_CXX_FLAGS="-fPIC" ..
make -j$(nproc)

# 2. 单独编译 main.cc（关键！sense_voice_free 等函数只在此文件中）
cd ..
g++ -c -fPIC -std=c++17 -I. -Isense-voice/csrc \
  -Ibuild/_deps/ggml-src/include \
  sense-voice/csrc/main.cc -o /tmp/main.o

# 3. 编译 wrapper 为共享库
g++ -shared -fPIC -std=c++17 \
  -I. -Isense-voice/csrc \
  -Ibuild/_deps/ggml-src/include \
  sense-voice/csrc/sensevoice_wrapper.cpp \
  /tmp/main.o \
  build/lib/libsense-voice-core.a \
  build/lib/libcommon.a \
  -Lbuild/lib -lggml -lggml-base -lggml-cpu \
  -o libsensevoice.so \
  -lpthread -ldl

# 4. 复制到项目目录
cp libsensevoice.so /home/dministrator/my-agent/libs/
```

#### 使用示例

```python
from ding.voice_recognition import recognize_audio

# 识别音频文件（支持 wav/mp3/amr 等）
text = recognize_audio("/tmp/voice_message.wav")
print(text)  # 输出：你好，请问有什么可以帮您的吗？

# 模型在第一次调用时自动加载，后续识别复用
```

#### 性能

| 指标 | 数值 |
|------|------|
| 首次加载 | ~0.9s（含模型加载） |
| 后续识别 | ~0.25s |
| 显存占用 | ~260MB（GPU） |

#### 环境要求

```bash
# 必须设置 LD_LIBRARY_PATH，否则找不到 libggml.so
export LD_LIBRARY_PATH=/home/dministrator/SenseVoice.cpp/build/lib:$LD_LIBRARY_PATH
```

---

### 5.4 文本转语音（TTS）- Piper

#### 架构

```
文本 → text_to_speech.py → ctypes → libpiper_tts.so → Piper C++ API → ONNX Runtime → WAV 音频
```

**特点**：
- **源码集成**（非命令行调用）
- 模型轻量（~63MB），推理极快
- **纯 CPU 运行**，零显存占用
- 支持中文、英文等多种语言

#### 编译方法

在 Piper 源码目录执行：

```bash
cd /opt/piper-src

# 1. 配置并编译
mkdir -p build && cd build
cmake -DCMAKE_CXX_FLAGS="-fPIC" ..
make -j$(nproc) piper_tts

# 编译产物：build/libpiper_tts.so
```

#### 使用示例

```python
from ding.text_to_speech import text_to_speech

# 将文本转为语音
audio_path = text_to_speech("你好，我是钉钉机器人助手。")
print(audio_path)  # 输出：/tmp/piper_tts_1234567890.wav

# 指定输出路径
audio_path = text_to_speech(
    "今天天气不错，适合出去散步。",
    output_path="/tmp/greeting.wav"
)
```

#### 性能

| 指标 | 数值 |
|------|------|
| 模型加载 | ~0.3s |
| 文本合成 | ~0.15-0.5s |
| 显存占用 | **0**（纯 CPU） |
| 模型大小 | ~63MB |

#### 环境要求

```bash
# 设置库搜索路径
export LD_LIBRARY_PATH=/opt/piper-src/build/pi/lib:$LD_LIBRARY_PATH
```

---

### 5.5 文件架构

```
# 项目目录（轻量，只含代码）
my-agent/
├── ding/
│   ├── voice_recognition.py      # ASR Python 封装
│   ├── text_to_speech.py         # TTS Python 封装
│   └── ...
├── libs/
│   └── libsensevoice.so          # SenseVoice 共享库
├── sense-voice-wrapper/
│   └── sensevoice_wrapper.cpp    # SenseVoice C wrapper 源码备份
└── README.md

# SenseVoice 源码目录（含模型）
/home/dministrator/SenseVoice.cpp/
├── models/
│   └── sense-voice-small-q6_k.gguf    # ASR 模型 (~230MB)
├── build/
│   └── lib/
│       └── libggml.so                 # 运行时依赖
└── sense-voice/csrc/
    └── sensevoice_wrapper.cpp         # C wrapper（新增）

# Piper 源码目录（含模型）
/opt/piper-src/
├── models/
│   ├── zh_CN-huayan-medium.onnx       # TTS 模型 (~63MB)
│   └── zh_CN-huayan-medium.onnx.json  # 模型配置
├── build/
│   ├── libpiper_tts.so                # 编译产物
│   └── pi/lib/
│       └── libonnxruntime.so          # 运行时依赖
└── src/cpp/
    └── piper_wrapper.cpp              # C wrapper（新增）
```

---

### 5.6 常见问题

#### ASR (SenseVoice)

| 问题 | 原因 | 解决 |
|------|------|------|
| `libggml.so: cannot open` | 未设置 LD_LIBRARY_PATH | `export LD_LIBRARY_PATH=/home/dministrator/SenseVoice.cpp/build/lib:$LD_LIBRARY_PATH` |
| `undefined reference to sense_voice_free` | 未链接 main.o | 确保编译时包含 `/tmp/main.o` |
| `relocation R_X86_64_32S` | 静态库未用 -fPIC 编译 | 删除 build 目录重新 cmake |

#### TTS (Piper)

| 问题 | 原因 | 解决 |
|------|------|------|
| `libonnxruntime.so: cannot open` | 未设置 LD_LIBRARY_PATH | `export LD_LIBRARY_PATH=/opt/piper-src/build/pi/lib:$LD_LIBRARY_PATH` |
| `piper_initialize: undefined symbol` | 共享库未正确导出 | 确保 C wrapper 中使用 `__attribute__((visibility("default")))` |
| 模型加载失败 | 模型路径错误 | 检查 `/opt/piper-src/models/` 下是否有模型文件 |

---

## 6. 通信协议

### 5.1 Master ↔ Worker 通信

**方式**：HTTP REST API

**创建 Agent**：
```http
POST http://localhost:4097/agent/create
Content-Type: application/json

{
  "name": "coder",
  "type": "python",
  "system_prompt": "你是一个 Python 专家"
}

# 返回
{
  "success": true,
  "agent": {
    "name": "coder",
    "port": 4098,
    "status": "running",
    "pid": 12345
  }
}
```

**发送指令**：
```http
POST http://localhost:4097/agent/coder/send
Content-Type: application/json

{
  "instruction": "写一个快速排序算法",
  "session_id": "uuid-xxx",
  "timeout": 120
}

# 返回
{
  "success": true,
  "result": {
    "stdout": "代码已生成...",
    "files": ["/home/user/agents/coder/quicksort.py"]
  }
}
```

**查询状态**：
```http
GET http://localhost:4097/agent/list

# 返回
{
  "agents": [
    {"name": "master", "port": 4097, "status": "running"},
    {"name": "coder", "port": 4098, "status": "running"},
    {"name": "ops", "port": 4099, "status": "stopped"}
  ]
}
```

### 5.2 Worker → Master 汇报

Worker 定期向 Master 汇报状态：

```http
POST http://localhost:4097/agent/heartbeat
Content-Type: application/json

{
  "name": "coder",
  "status": "running",
  "tasks_completed": 42,
  "current_task": null,
  "uptime": 3600
}
```

### 5.3 主进程 ↔ Agent 插件通信

主进程通过文件系统或共享内存与 Worker 进程通信：

```
/tmp/autobot_tasks/
├── task.json      # 主进程写入任务
└── result.json    # Worker 进程写入结果
```

---

## 6. 使用场景示例

### 场景 1：远程写代码

**用户**（手机钉钉语音）：
> "帮我写一个爬取豆瓣 Top250 电影的 Python 脚本"

**系统处理**：
1. 钉钉接收语音 → 语音识别 → 文本
2. 无 #指令 → 默认交给 ai_image（AI 对话）
3. AI 判断需要写代码 → 内部调用 `#agent coder`
4. 创建/复用 coder Agent
5. 发送指令给 coder Agent
6. coder Agent 生成代码并保存到文件
7. 返回代码内容和文件路径
8. 主进程发送结果给用户

**回复**：
> "已为你生成豆瓣爬虫脚本，保存在 `~/agents/coder/douban_spider.py`，核心逻辑：
> 1. 使用 requests 请求豆瓣页面
> 2. 使用 BeautifulSoup 解析 HTML
> 3. 提取电影名称、评分、链接
> 4. 保存为 CSV 文件
>
> 你可以运行 `#agent coder 执行这个脚本` 来测试"

### 场景 2：多 Agent 协作

**用户**：
> `#agent master 创建数据分析团队，分析服务器日志`

**系统处理**：
1. Master 解析指令
2. 创建多个 Agent：
   - `data-collector`：负责收集日志
   - `data-parser`：负责解析和清洗
   - `data-analyzer`：负责分析和生成报告
3. Master 协调任务顺序：
   - 先让 collector 收集日志
   - 然后 parser 解析
   - 最后 analyzer 生成报告
4. 汇总结果返回用户

### 场景 3：服务器运维

**用户**（手机钉钉）：
> `#agent ops 查看服务器状态，如果有异常就重启 Nginx`

**系统处理**：
1. 指令路由到 ops Agent
2. ops Agent 执行：
   - `df -h` 检查磁盘
   - `free -m` 检查内存
   - `systemctl status nginx` 检查服务
3. 发现 Nginx 异常
4. 执行 `sudo systemctl restart nginx`
5. 返回操作结果

### 场景 4：Agent 管理

**用户**：
> `#agent master 列出所有 Agent`

**回复**：
> "当前运行的 Agent：
> - 🤖 master (端口 4097) - 运行中 - 管理中枢
> - 💻 coder (端口 4098) - 运行中 - 已完成 12 个任务
> - 🔧 ops (端口 4099) - 已停止 - 上次运行 2 小时前
> - 📊 data (端口 4100) - 运行中 - 正在执行数据分析"

---

## 7. 目录结构

```
my-agent/
├── README.md                      # 本文档
├── img.sh                         # 本地图像生成脚本
├── ding/                          # 钉钉机器人核心
│   ├── autobot_dingtalk.py        # 主进程：钉钉消息接收
│   ├── task_worker.py             # Worker：任务执行
│   ├── executor.py                # 执行器：Shell/Python
│   ├── ai.py                      # AI 模块：任务分析
│   ├── siliconflow.py             # SiliconFlow API
│   ├── dingtalk.py                # 钉钉 API 封装
│   ├── config.py                  # 配置管理
│   ├── prompt.py                  # 系统提示词
│   ├── guardian.py                # 守护进程
│   ├── logger.py                  # 日志模块
│   ├── nano_banana.py             # 图像生成
│   ├── master.py                  # Master Agent 管理
│   ├── agent.md                   # Agent 使用指南
│   ├── tasks/                     # 插件目录
│   │   ├── __init__.py
│   │   ├── base.py                # 任务基类
│   │   ├── registry.py            # 注册表
│   │   ├── shell.py               # #shell 指令
│   │   ├── code.py                # #code 指令
│   │   ├── python.py              # #python 指令
│   │   ├── agent.py               # #agent 指令
│   │   ├── img.py                 # #img 指令
│   │   ├── ai_image.py            # 默认 AI 对话
│   │   ├── ai_analyze.py          # 图片分析
│   │   └── ...
│   └── logs/                      # 日志目录
├── agents/                        # Agent 工作目录（自动创建）
│   ├── registry.json              # Agent 注册表
│   ├── master/                    # Master Agent
│   │   ├── config.json
│   │   └── work/                  # 工作文件
│   ├── coder/                     # 代码专家 Agent
│   │   ├── config.json
│   │   └── work/
│   └── ...
└── .env                           # 环境变量
```

---

## 8. 部署与启动

### 8.1 首次部署

```bash
# 1. 克隆代码
git clone <repo> my-agent
cd my-agent

# 2. 安装依赖
pip install -r requirements.txt

# 3. 配置环境变量
cp .env.example .env
# 编辑 .env 填入钉钉密钥、API Key 等

# 4. 创建 Agent 目录
mkdir -p agents
```

### 8.2 启动脚本 start.sh

项目根目录提供 `start.sh` 一键启动/停止所有服务。

**启动所有服务：**
```bash
./start.sh start
```
启动以下 3 个进程：
- **bot** (`autobot_dingtalk.py`) - 钉钉消息接收，日志 `/tmp/autobot_bot.log`
- **worker** (`task_worker.py`) - 任务执行，日志 `/tmp/autobot_worker.log`
- **master** (opencode serve) - Agent 管理，运行在 tmux session 中

**停止所有服务：**
```bash
./start.sh stop
```

**重启：**
```bash
./start.sh restart
```

**查看运行状态：**
```bash
# 查看 bot 和 worker 进程
ps aux | grep -E "autobot_dingtalk|task_worker"

# 查看 master
ps aux | grep "opencode serve"

# 查看日志
tail -f /tmp/autobot_bot.log
tail -f /tmp/autobot_worker.log
```

### 8.3 通过钉钉控制

启动后，所有操作都可通过钉钉完成：

```
# 查看帮助
#agent help

# 创建 Agent
#agent master create coder --type python

# 发送指令
#agent coder 写一个 WebSocket 客户端

# 查看状态
#agent master list

# 停止 Agent
#agent master destroy coder
```

---

## 9. 安全设计

### 9.1 命令黑名单

在 `config.py` 中配置，禁止执行危险命令：
- `rm -rf /`
- `mkfs`, `dd if=`
- `shutdown`, `reboot`
- `iptables`, `ufw`
- `docker`, `kubectl`

### 9.2 Agent 隔离

- 每个 Agent 独立进程、独立目录
- Agent 之间不能直接访问对方文件
- 敏感操作需二次确认

### 9.3 权限控制

- 区分"只读 Agent"和"可写 Agent"
- 系统级操作需要特殊权限
- 生产环境建议启用 HTTP Basic Auth

---

## 10. 扩展性设计

### 10.1 新增 Agent 类型

只需定义系统提示词和配置：

```python
# tasks/agent_types.py
AGENT_TYPES = {
    "python": {
        "system_prompt": "你是 Python 专家...",
        "tools": ["python", "pip", "pytest"]
    },
    "frontend": {
        "system_prompt": "你是前端开发专家...",
        "tools": ["node", "npm", "vite"]
    },
    "ops": {
        "system_prompt": "你是运维专家...",
        "tools": ["docker", "kubectl", "nginx"]
    }
}
```

### 10.2 新增消息类型

在 `autobot_dingtalk.py` 的 `process` 方法中添加处理逻辑即可。

### 10.3 新增插件

在 `tasks/` 目录下创建新文件，继承 `BaseTask`：

```python
from tasks.base import BaseTask, TaskResult

class MyTask(BaseTask):
    task_type = "mycommand"
    
    def execute(self, content, session_webhook=None):
        return TaskResult.ok("执行成功")
```

---

## 11.  roadmap

### Phase 1: 基础架构 ✅
- [x] 钉钉消息接收与回复
- [x] 插件化任务系统
- [x] 基础 Agent 管理

### Phase 2: Master Agent 🔄
- [ ] Master Agent 自动启动
- [ ] Agent 生命周期管理
- [ ] 指令路由与分发
- [ ] 状态监控与心跳

### Phase 3: 多模态支持 📋
- [ ] 语音消息自动识别
- [ ] 图片理解与生成
- [ ] 文件上传与下载

### Phase 4: 高级功能 📋
- [ ] Agent 间协作
- [ ] 长任务持久化
- [ ] 结果文件自动发送
- [ ] 权限与审计日志

### Phase 5: 生态扩展 📋
- [ ] Web 管理界面
- [ ] 更多 Agent 类型
- [ ] 插件市场
- [ ] 多用户支持

---

*文档版本: 1.0*
*更新日期: 2026-05-12*
