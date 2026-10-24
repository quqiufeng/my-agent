# My Agent — 会看见、会验证、会迭代的远程操作 Agent

> **一句话**：把**手机微信 / 语音**当作目标输入，交给本地 `opencode` 大脑理解，再通过**白名单工具**操作电脑、摄像头、手机和其他设备；执行后用截图、OCR、DOM 和状态回读验证结果，失败就自动修。
>
> 它的本质是「**入口只产文本 → 单脑决策 → 白名单执行 → 观察验证 → 按来源回程**」。
>
> 长期目标：**人只加设备、描述需求；系统自己发现能力缺口、生成工具、验证结果、迭代能力边界。**

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
   [微信输入] xxx ──────────▶│                        │   │  screenshot.sh / wechat_shot.sh│
                            └───────────────────────┘   │  wechat_shot.sh / dev.sh   │
                                                        └────────────────────────────┘
                                                                    │
                                                                    ▼
                                            语音→ say.sh 出声   微信→ wechat_send.sh 回发
```

> **白名单工具现有 36 个**：设备扫描/拓扑、说话/微信/截屏、音乐/找文件、文生图/视频、行情大屏、摄像头四路与识别、微博/抖音、桌面终端、扫地机、**电纸书**。
> 清单与各工具规则由 `operator/plugin.sh index` **自动生成**到 `operator/TOOLS.md`（大脑经 `instructions` 加载），**新增工具无需手改契约**。

三条设计原则：

1. **入口只产文本**：语音、微信两条入口都只做「转成文字 + 打前缀」，不掺业务逻辑。
2. **单脑**：全项目只有一个常驻 `opencode`（4097），不跑多 Agent。
3. **能力=白名单**：大脑只能调用 `operator/tools/*` 里的脚本（三层白名单防护），其余命令一律拒绝。


---

## 它是什么，不是什么

**是**：

- 一个受控的家庭 / 工作室操作代理
- 一个能自我扩展工具、自己跑、自己看、自己修的迭代系统
- 一个把「设备 API + 截图/OCR + 摄像头 + 状态」组合成闭环的执行层

**不是**：

- 通用 Jarvis
- 无人值守的安全系统
- 能凭空变出物理能力的系统
- 能绕过白名单任意执行命令的系统

当前定位：**高可靠自动化代理 + 自开发/自测试助手**。

数字任务接近 L3.5，物理世界仍偏 L2；通用性会随模型和接入设备上移，但不会自动变成通用智能。

## 自我迭代飞轮

```text
人给目标 / 加设备
   → 发现能力缺口
   → 写工具 / 接 API / 学技能
   → 执行
   → 摄像头 / 截图 / OCR / DOM / 设备状态验证
   → 失败就修，成功就沉淀
   → 工具、测试、文档、失败样本进入库
   → 下一次更快、更稳、覆盖更广
```

每转一圈必须留下可复用资产：

- 一个新工具
- 一条成功判据
- 一个失败样本
- 一条设备能力描述
- 一条安全策略
- 一条回归测试

否则不是飞轮，只是重复劳动。

### 三个耦合飞轮

1. **能力飞轮**：设备越多 → 任务越多 → 工具越多 → 能接的设备更多
2. **可靠性飞轮**：失败越多 → 回归用例越多 → 成功率越高 → 敢放开更多 autonomy
3. **信任飞轮**：验证越充分 → 授权范围越大 → 可执行范围越大

第三个飞轮决定上限。没有信任，能力和可靠性都放不大。

### 飞轮需要棘轮

自我迭代最怕的不是慢，是倒退。必须有：

- 回归测试 / 黄金样本
- 失败回放
- 自动回滚
- 能力矩阵
- 安全策略

飞轮负责变强，棘轮负责不倒退。

## 能力上限

实际可达水平不是单一模型分数，而是：

> **实际能力 = min(模型认知上限, 设备动作上限, 验证闭环可信度, 安全/授权边界) − 时延/成本损耗**

- **模型**决定能不能想明白、能不能调用工具、能不能多模态理解
- **设备**决定能不能真正做到；没有对应硬件，代码变不出物理能力
- **验证**决定 agent 是否真的知道“做成了”
- **安全**决定哪些动作允许发生
- **成本/时延**决定能不能规模化

所以框架不封顶，但“无上限”不等于“无约束”。

## 从“加设备”到“自动接入”

人真正需要提供的是：

1. **设备**：通电、联网、给凭据
2. **目标**：一句话说明要做什么
3. **边界**：哪些能做、哪些必须确认、哪些禁止

系统需要把设备变成可理解的接入契约：

- 地址与认证
- 能力清单
- 状态格式
- 安全动作（急停/限速/禁区）
- 成功判据

有了这些，agent 才能自动生成工具、自动验证；否则只能猜。

## 机器人：会提升上限，但不会自动通用

- 机器人有**高层技能 API**（goto / pick / patrol / dock）：当前架构可以当任务大脑，能力显著上移
- 机器人只有**底层电机/关节控制**：需要另加 ROS2/行为树/实时安全层，不能让 LLM 直接控电机
- 机器人是**通用人形/VLA**：理论上是通用管家，实际仍受感知、操作、安全、成本限制

结论：**接入机器人会把上限从“屏幕与设备代理”抬到“有限物理任务代理”，但通用性来自机器人本体智能 + 技能库 + 安全层，不是接入动作本身。**

## 当前验证闭环

- **代码**：修改 → 语法检查 → 运行 → 截图/日志/状态回读 → 修复 → 提交
- **UI**：自有 Web / Flutter / LVGL 强；微信、闭源 App、动态布局弱
- **摄像头**：能看“发生了什么”，但看不清小字、遮挡、盲区、夜景
- **设备**：手机 / Kindle / 桌面截图可读；设备 API 状态最可靠
- **物理世界**：摄像头是辅助证据，不是安全级证明

近期回归中的真实例子：`cdpd` 旧标签页、微信假成功、`term_progress` 未切 tab、YOLO 漏掉沙发上的人——都是靠“看见结果不对”发现并修的。

## 成熟度与下一步

| 阶段 | 状态 |
|---|---|
| L1 固定命令执行 | 已完成 |
| L2 单任务自动化 | 已完成 |
| L3 受控闭环（执行→验证→修复） | 当前 |
| L3.5 多设备 + 自开发 / UI 自测 | 当前接近 |
| L4 人只加设备/目标，系统自动接入与回归 | 下一阶段 |
| L5 开放世界通用管家 | 远未达到 |

L4 的关键不是再写更多工具，而是把四件事做成一等公民：

1. 设备注册表与能力描述
2. 目标/验收协议
3. 场景回归库与失败记忆
4. 安全策略与人工确认


---

## 目录结构

```
my-agent/
├── README.md                 # 本文档（整体架构）
├── AGENTS.md                 # 仓库级 agent 指南（开发/维护约定）
├── chrome.md / rule.md       # Chrome 控制、UTEL 编码规范（参考）
│
├── operator/                 # 【大脑】单脑 + 工具白名单（插件式）
│   ├── AGENTS.md             #   运行时契约（来源识别/回程/示例等散文）
│   ├── TOOLS.md              #   工具清单+规则（plugin.sh index 自动生成，instructions 加载）
│   ├── plugin.sh             #   轻插件：new 生成模板 / index 重建 TOOLS.md / list
│   ├── opencode.json         #   权限：默认全拒，仅放行 tools/*；instructions 加载 TOOLS.md
│   ├── .opencode/plugin/guard.js  # 兜底：拦截拼接命令
│   ├── start.sh              #   启动 tmux + opencode serve(4097)/attach
│   ├── tools/                #   36 个白名单工具（每个自带 @desc/@usage/@rule）
│   └── README.md
│
├── voice/                    # 【语音入口 + 输出】纯 C/C++，无 Python
│   ├── say.sh                #   文本 → USB 音响（sherpa-onnx + Kokoro）
│   ├── listen/               #   麦克风监听 → SenseVoice → 转发大脑
│   ├── tutor.sh              #   旧陪练内核（待专用 app 复用）
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
├── agentkit/kindle/          # 【电纸书】Kindle DXG 自研阅读器
│   ├── boot/src/             #   交叉编译源码/脚本/产物（LVGL+LuaJIT+FreeType）
│   ├── boot/lua/             #   界面逻辑 init.lua + 开发指南
│   └── boot/test/            #   kui 自动化/语音指令 + smoke.lua + 视觉回归
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
#    微信里发“ai助手 现在几点 / 放周杰伦 / 四个摄像头拼图 / 股票大屏”

# 4. 文本转语音（USB 音响）
voice/voice.sh say "你好"

# 5. 手机控制 / 自主测试闭环（ADB；手机开 USB 调试并授权）
operator/tools/phone.sh status   # 截屏 / 点击 / 中文输入 / 开应用（详见根 AGENTS.md）

# 7. 电纸书（Kindle DXG，USB + ssh 免密）
operator/tools/ebook.sh say "读异类"     # 读书/下一页/跳到第20页/字号大/目录/书架
operator/tools/ebook.sh shot /tmp/e.png  # 截当前屏（可再 wechat_send_file.sh 发回）
operator/tools/ebook.sh speak            # 朗读当前页

# 新增一个“能力”（不用改 AGENTS.md）
operator/tools/netmap.sh scan      # 扫描设备 → devices.json / NETWORK.md / devices.env
operator/plugin.sh new mytool      # 生成模板 → 写实现 → index → 重启大脑
```

---

## 安全模型（白名单，三层）

> 微信/语音内容是不可信输入，却要触发本机执行。为此设三层：

1. **权限**（`operator/opencode.json`）：`bash` 默认 `deny`、只放行 `tools/*`；`read/edit/webfetch/task` 全部 `deny`。
2. **兜底插件**（`operator/.opencode/plugin/guard.js`）：执行前正则校验，禁止 `&&`、`;`、`|`、重定向等拼接绕过。
3. **契约**（`operator/AGENTS.md` + `operator/TOOLS.md`）：告诉大脑“只能调用白名单里的 36 个工具，不认识的请求就拒绝”。

回程规则：`[语音输入]` → `say.sh` / `wechat_send.sh`；`[微信输入:<会话名>]` → `wechat_send.sh --to <会话名>`（默认「文件传输助手」）。

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
| LuaJIT libxdo (xdo.lua) / xclip / ImageMagick | 桌面窗口操作 / 大屏渲染 | wechat-ocr / operator |
| VLC (`cvlc`/`vlc`) + `jq` | 音乐播放、行情解析 | operator |
| WordCard 霞鹜文楷 / JetBrains Mono 字体 | 行情大屏渲染 | operator |
| PipeWire (`pw-play`) / aplay / espeak-ng | 音频播放与兜底 | voice |
| 同花顺 fuyao REST（需 API Key） | 行情大屏 | operator |
| 小龙虾（微信客户端） | 微信窗口 | wechat-ocr |

> 运行时**不依赖 Python**；模型/二进制在 `/opt`、`/data/models`，不入库。

---

## 状态

- ✅ 语音转文本（SenseVoice.cpp，中/英）
- ✅ 文本转语音（Kokoro → USB 音响，中英音色）
- ✅ **语音克隆发声**（CosyVoice3 的 C++/GGUF 移植 [Lourdle/cosyvoice.cpp] + LuaJIT FFI）：可**指定某人音色**发声；音色用 `tools/voices.sh` 注册/管理，`tools/say.sh --voice <名>` 使用
- ✅ **图片视频**（`img_video.sh`）：按提示词出图 → 合成竖版 MP4；已有图片可直接 `--imgdir` 复用；默认不发微信
- ✅ 摄像头窗口 / 人脸门控 / 统一界面
- ✅ 微信 OCR 机器人（搜索/发送/截图/监控）
- ✅ 单脑 + **插件式白名单**（`plugin.sh` 生成 `TOOLS.md`，当前 **36 个工具**）
- ✅ 微信入口：白名单会话；后台**不抢焦点**读预览，带 `ai助手` 标签触发 → `[微信输入:<会话>]` 转发 → 回复带 `ai助手` 前缀回来源
- ✅ 能力：设备扫描/拓扑 / 音乐 / 截屏 / 找文件(本机+NAS) / 文生图 / 行情大屏 / 四路摄像头与识别 / 微博 / 抖音 / 语音克隆 / 终端进度 / 扫地机 / 电纸书
- ✅ 股票数据源：同花顺 fuyao（REST，API Key 在 `~/.env`）
- ✅ **点阵风 UI**：行情大屏（`dash.sh`：TSV→HTML(Canvas)→headless Chrome 截图）与统一界面（`voice/app` 状态栏）采用暗色点阵风；组件来自 [karminski-design-skills](https://github.com/karminski/karminski-design-skills)（CC BY-NC-SA 4.0，署名见 `operator/tools/dotkit/NOTICE.md`）
- ✅ **手机控制**（`phone.sh`，ADB：截屏/点击/滑动/中文输入/开应用）+ **手机微信自主测试闭环**（手机发指令 → 大脑执行 → 回程到手机）
- ✅ **电纸书**（`ebook.sh` → `agentkit/kindle`）：自研 LVGL 阅读器（书架/阅读/目录/进度/三档字号）+ **文本指令**（`/tmp/ui_say`，语音/无障碍）+ **agent 闭环测试**（`kui state/tap/say/dump/shot`，截图可被 AI 直接看）
- ⏳ 生产守护（systemd）待定；微信读屏受「最小化/列表滚动」限制
- ⏳ L4：设备注册表、目标验收协议、回归库、安全策略

> 当前不是“通用 Jarvis”，而是一个**已验证大量数字/家庭任务、正在向 L4 演进的自迭代代理**。

---

*文档版本: 5.2 · 更新日期: 2026-10-24*
