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

> **白名单工具现有 21 个**：说话/发微信（`say`/`wechat_send`/`wechat_send_file`）、截屏、音乐、美剧/电影、USB 摄像头拍照、找文件（本机+NAS）、出图、股票行情/估值/财务、行情大屏、开发进度、备忘、英语口语陪练、记单词、开应用/浏览器、集群管理、结果分发、时间。
> 清单与各工具规则由 `operator/plugin.sh index` **自动生成**到 `operator/TOOLS.md`（大脑经 `instructions` 加载），**新增工具无需手改契约**。

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
├── operator/                 # 【大脑】单脑 + 工具白名单（插件式）
│   ├── AGENTS.md             #   运行时契约（来源识别/回程/示例等散文）
│   ├── TOOLS.md              #   工具清单+规则（plugin.sh index 自动生成，instructions 加载）
│   ├── plugin.sh             #   轻插件：new 生成模板 / index 重建 TOOLS.md / list
│   ├── opencode.json         #   权限：默认全拒，仅放行 tools/*；instructions 加载 TOOLS.md
│   ├── .opencode/plugin/guard.js  # 兜底：拦截拼接命令
│   ├── start.sh              #   启动 tmux + opencode serve(4097)/attach
│   ├── tools/                #   21 个白名单工具（每个自带 @desc/@usage/@rule）
│   └── README.md
│
├── voice/                    # 【语音入口 + 输出】纯 C/C++，无 Python
│   ├── say.sh                #   文本 → USB 音响（sherpa-onnx + Kokoro）
│   ├── listen/               #   麦克风监听 → SenseVoice → 转发大脑
│   ├── tutor.sh              #   英语口语陪练（[英语口语] 前缀 + 英文音色）
│   ├── camera/               #   摄像头窗口（SDL2 + 人脸门控）
│   ├── app/                  #   统一界面：画面 + 人脸门控 + 语音 + 状态栏
│   └── README.md
│
├── wechat-ocr/               # 【微信入口】LuaJIT + C++ + ONNX Runtime
│   ├── wechat_robot.lua      #   统一 Lua API（搜索/发送/截图/监控/未读）
│   ├── bridge.lua / bridge.sh #   白名单会话后台读预览 → 转发 [微信输入:<会话>]（不抢焦点）
│   ├── lua/wechat_ocr/       #   核心模块（init/chrome/badge_detect/watcher，仓库正本）
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

# 3. 微信入口（白名单会话 → 读预览 → 大脑；不抢焦点）
wechat-ocr/bridge.sh
#    微信里发“ai助手 现在几点 / 放周杰伦 / 拍一张 / 看生活大爆炸 / 看下茅台 / 股票大屏”

# 4. 英语口语陪练（麦克风，回复用英文音色）
voice/voice.sh tutor

# 5. 文本转语音（USB 音响）
voice/voice.sh say "你好"

# 6. 手机控制 / 自主测试闭环（ADB；手机开 USB 调试并授权）
operator/tools/phone.sh status   # 截屏 / 点击 / 中文输入 / 开应用（详见根 AGENTS.md）

# 新增一个“能力”（不用改 AGENTS.md）
operator/plugin.sh new mytool      # 生成模板 → 写实现 → index → 重启大脑
```

---

## 安全模型（白名单，三层）

> 微信/语音内容是不可信输入，却要触发本机执行。为此设三层：

1. **权限**（`operator/opencode.json`）：`bash` 默认 `deny`、只放行 `tools/*`；`read/edit/webfetch/task` 全部 `deny`。
2. **兜底插件**（`operator/.opencode/plugin/guard.js`）：执行前正则校验，禁止 `&&`、`;`、`|`、重定向等拼接绕过。
3. **契约**（`operator/AGENTS.md` + `operator/TOOLS.md`）：告诉大脑“只能调用白名单里的 26 个工具，不认识的请求就拒绝”。

回程规则：`[语音输入]` → `say.sh` / `wechat_send.sh`；`[微信输入:<会话名>]` → `wechat_send.sh --to <会话名>`（默认「文件传输助手」）；`[英语口语]` → `say.sh` 英文音色。

---

## 运行依赖

| 组件 | 用途 | 模块 |
|------|------|------|
| opencode + tmux | 单脑与常驻会话 | operator |
| SenseVoice.cpp + gguf | 语音转文本（纯 C++） | voice |
| sherpa-onnx + Kokoro | 文本转语音（纯 C++） | voice |
| Lourdle/cosyvoice.cpp + GGUF | 克隆音色 TTS（C++/GGML，LuaJIT FFI；`/opt/cosyvoice.cpp`） | voice |
| SDL2 + OpenCV + ALSA | 统一界面 / 摄像头 / 采集 | voice |
| LuaJIT + ONNX Runtime GPU | 微信 OCR | wechat-ocr |
| PaddleOCR PP-OCRv4 | 聊天文字识别 | wechat-ocr |
| xdotool / xclip / ImageMagick | 桌面窗口操作 / 大屏渲染 | wechat-ocr / operator |
| VLC (`cvlc`/`vlc`) + `jq` | 音乐/美剧播放、行情解析 | operator |
| WordCard `libtxt2png.so` + 霞鹜文楷 | 单词卡/大屏渲染（纯 C ABI） | operator |
| PipeWire (`pw-play`) / aplay / espeak-ng | 音频播放与兜底 | voice |
| 同花顺 fuyao REST（需 API Key） | 股票行情/财务/大屏 | operator |
| 小龙虾（微信客户端） | 微信窗口 | wechat-ocr |

> 运行时**不依赖 Python**；模型/二进制在 `/opt`、`/data/models`，不入库。

---

## 状态

- ✅ 语音转文本（SenseVoice.cpp，中/英）
- ✅ 文本转语音（Kokoro → USB 音响，中英音色）
- ✅ **语音克隆发声**（CosyVoice3 的 C++/GGUF 移植 [Lourdle/cosyvoice.cpp] + LuaJIT FFI）：可**指定某人音色**发声；音色用 `tools/voices.sh` 注册/管理，`tools/say.sh --voice <名>` 使用
- ✅ **动画短片**（`img_video.sh`）：用出图功能生成若干动漫分镜 → 配音+字幕 → 竖版短片发微信；默认主题=中国传统童话（内置《神笔马良》分镜）
- ✅ 摄像头窗口 / 人脸门控 / 统一界面
- ✅ 微信 OCR 机器人（搜索/发送/截图/监控）
- ✅ 单脑 + **插件式白名单**（`plugin.sh` 生成 `TOOLS.md`，26 工具）
- ✅ 微信入口：白名单会话；后台**不抢焦点**读预览，带 `ai助手` 标签触发 → `[微信输入:<会话>]` 转发 → 回复带 `ai助手` 前缀回来源
- ✅ 能力：音乐 / 美剧·电影(VLC) / USB 拍照 / 截屏 / 找文件(本机+NAS) / 出图 / 股票行情·估值·财务 / 行情大屏 / 开发进度 / 备忘 / **英语口语陪练** / **记单词(发音判定)** / 开应用·浏览器 / 集群 / 结果分发
- ✅ 股票数据源：同花顺 fuyao（REST，API Key 在 `~/.env`）
- ✅ **点阵风 UI**：行情大屏（`dash.sh`：TSV→HTML(Canvas)→headless Chrome 截图）与统一界面（`voice/app` 状态栏）采用暗色点阵风；组件来自 [karminski-design-skills](https://github.com/karminski/karminski-design-skills)（CC BY-NC-SA 4.0，署名见 `operator/tools/dotkit/NOTICE.md`）
- ✅ **手机控制**（`phone.sh`，ADB：截屏/点击/滑动/中文输入/开应用）+ **手机微信自主测试闭环**（手机发指令 → 大脑执行 → 回程到手机）
- ⏳ 生产守护（systemd）待定；微信读屏受「最小化/列表滚动」限制

---

*文档版本: 5.0 · 更新日期: 2026-10-06*
