# My Agent — 用微信 / 语音远程操作电脑

> **一句话**：一个常驻服务，把**手机微信**或**语音**当作遥控器，交给一个本地 `opencode` 大脑理解，再通过**白名单脚本**操作这台电脑（发微信、放音、截屏、开应用、操作浏览器、管理集群）。

它的本质是「**入口只产文本 → 单脑决策 → 白名单工具执行 → 按来源回程**」。

---

## 架构总览

```
   输入（入口层，只产文本）              决策（单脑）                执行（白名单工具层）        回程
┌───────────────────────┐
│ 语音  voice/          │
│  麦克风 → VAD →        │  [语音输入] xxx
│  SenseVoice.cpp (C++) │ ───────────┐
└───────────────────────┘            │
                                     ▼
┌───────────────────────┐   ┌───────────────────────┐   ┌────────────────────────────┐
│ 微信  wechat-ocr/     │   │  opencode  (127.0.0.1 │   │ tools/ 白名单（唯一入口）   │
│  截图 → PP-OCRv4 →     │──▶│  :4097, tmux 常驻)     │──▶│  say.sh         → USB 音响  │
│  聊天文本提取          │   │  读 AGENTS.md 契约      │   │  wechat_send.sh → 微信      │
└───────────────────────┘   │  只能调用 tools/*       │   │  wechat_send_file.sh        │
   [微信输入] xxx ──────────▶│                        │   │  screenshot.sh / open_app.sh│
                            └───────────────────────┘   │  browser.sh / remote.sh     │
                                                        └────────────────────────────┘
                                                                    │
                                                                    ▼
                                            语音→ say.sh 出声   微信→ wechat_send.sh 回发
```

三条设计原则：

1. **入口只产文本**：语音、微信两条入口都只做「转成文字 + 打前缀」，不掺业务逻辑。
2. **单脑**：全项目只有一个常驻 `opencode`（4097），不跑多 Agent。
3. **能力=白名单**：大脑只能调用 `operator/tools/*` 里的脚本（三层白名单防护），其余命令一律拒绝。

---

## 目录结构

```
my-agent/
├── README.md                 # 本文档（整体架构）
├── AGENTS.md                 # 仓库级 agent 指南（开发/维护约定）
├── remote.sh                 # tmux + opencode 会话/集群管理脚本（大脑的一把工具）
├── chrome.md / rule.md       # Chrome 控制、UTEL 编码规范（参考）
│
├── operator/                 # 【大脑】单脑 + 工具白名单
│   ├── AGENTS.md             #   ★ 运行时契约（大脑读：来源识别/回程/白名单/禁止项）
│   ├── opencode.json         #   权限：默认全拒，仅放行 tools/*
│   ├── .opencode/plugin/guard.js  # 兜底：拦截拼接命令
│   ├── start.sh              #   启动 tmux + opencode serve(4097)/attach
│   ├── tools/                #   白名单工具（say/wechat_send/screenshot/open_app/browser/remote）
│   └── README.md
│
├── voice/                    # 【语音入口 + 输出】纯 C/C++，无 Python
│   ├── say.sh                #   文本 → USB 音响（sherpa-onnx + Kokoro）
│   ├── listen/               #   麦克风监听 → SenseVoice → 转发大脑
│   ├── camera/               #   摄像头窗口（SDL2 + 人脸门控）
│   ├── app/                  #   统一界面：画面 + 人脸门控 + 语音 + 状态栏
│   └── README.md
│
├── wechat-ocr/               # 【微信入口】LuaJIT + C++ + ONNX Runtime
│   ├── wechat_robot.lua      #   统一 Lua API（搜索/发送/截图/监控/未读）
│   ├── bridge.lua / bridge.sh #   monitor → 转发 [微信输入]
│   ├── lua/wechat_ocr/       #   核心模块（init/chrome/badge_detect，仓库正本）
│   ├── src/ lib/             #   截图 + PP-OCRv4 C++ 封装
│   └── README.md / WECHAT_OCR.md
│
├── sense-voice-wrapper/      # SenseVoice ASR C 封装源码（备用）
├── joycaption-wrapper/       # VLM 图标识别 C 封装（备用）
└── models/                   # 模型目录（.gitignore 排除大文件）
```

---

## 快速开始

```bash
# 1. 启动大脑（tmux + opencode，端口 4097）
operator/start.sh                # 前台；--bg 后台

# 2. 语音入口（麦克风 → 文本 → 大脑）
voice/voice.sh listen            # 常驻监听
voice/voice.sh app               # 或：统一界面（画面+语音+状态栏）

# 3. 微信入口（微信窗口 → OCR → 大脑）
wechat-ocr/bridge.sh

# 4. 文本转语音（USB 音响）
voice/voice.sh say "你好"
```

---

## 安全模型（白名单，三层）

> 微信/语音内容是不可信输入，却要触发本机执行。为此设三层：

1. **权限**（`operator/opencode.json`）：`bash` 默认 `deny`、只放行 `tools/*`；`read/edit/webfetch/task` 全部 `deny`。
2. **兜底插件**（`operator/.opencode/plugin/guard.js`）：执行前正则校验，禁止 `&&`、`;`、`|`、重定向等拼接绕过。
3. **契约**（`operator/AGENTS.md`）：明确告诉大脑“只能做白名单里的七件事，不认识的请求就拒绝”。

回程规则：`[语音输入]` → `say.sh`；`[微信输入]` → `wechat_send.sh`（默认发「文件传输助手」，可 `--to` 指定联系人）。

---

## 运行依赖

| 组件 | 用途 | 模块 |
|------|------|------|
| opencode + tmux | 单脑与常驻会话 | operator |
| SenseVoice.cpp + gguf | 语音转文本（纯 C++） | voice |
| sherpa-onnx + Kokoro | 文本转语音（纯 C++） | voice |
| SDL2 + OpenCV + ALSA | 统一界面 / 摄像头 / 采集 | voice |
| LuaJIT + ONNX Runtime GPU | 微信 OCR | wechat-ocr |
| PaddleOCR PP-OCRv4 | 聊天文字识别 | wechat-ocr |
| xdotool / xclip / ImageMagick | 桌面窗口操作 | wechat-ocr / operator |
| PipeWire (`pw-play`) / aplay / espeak-ng | 音频播放与兜底 | voice |
| 小龙虾（微信客户端） | 微信窗口 | wechat-ocr |

> 运行时**不依赖 Python**；模型/二进制在 `/opt`、`/data/models`，不入库。

---

## 状态

- ✅ 语音转文本（SenseVoice.cpp，实测中文识别正确）
- ✅ 文本转语音（Kokoro → USB 音响，实测出声）
- ✅ 摄像头窗口 / 人脸门控 / 统一界面
- ✅ 微信 OCR 机器人（搜索/发送/截图/监控）
- ✅ 单脑 + 工具白名单骨架（operator/）
- ✅ 微信入口端到端：后台轮询「文件传输助手」未读红点（双重认证，不抢焦点、不点开会话、红点保留）→ 读预览转发大脑 → 大脑回复带 `#ai助手` 前缀
- ⏳ 模型后端与生产守护（systemd）待定

---

*文档版本: 4.0 · 更新日期: 2026-10-04*
