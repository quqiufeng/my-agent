# AGENTS.md — 仓库级指南

> 本文件是给**在本仓库开发/维护的 agent 与人**看的项目说明与约定。
> **运行时的“大脑契约”不在这里**，而在 [`operator/AGENTS.md`](operator/AGENTS.md)（opencode 大脑从 `operator/` 工作目录加载它）。改运行规则请改那份，别改这份。

---

## 项目是什么

把「手机微信 / 语音」变成对这台电脑的远程遥控：

```
入口（只产文本）            大脑（单脑）                  执行（白名单工具）           回程
语音 SenseVoice.cpp  ─┐
                      ├─▶ opencode(4097) 读 AGENTS.md ─▶ operator/tools/*.sh ─▶ 本机操作
微信 PP-OCRv4 OCR    ─┘
```

三条铁律：**入口只产文本**、**单脑**、**能力=白名单脚本**。

---

## 目录职责

| 路径 | 职责 |
|------|------|
| `operator/` | 大脑：`opencode.json` 权限、`guard.js` 兜底、`tools/` 白名单、`AGENTS.md` 运行时契约 |
| `voice/` | 语音入口与输出：`listen`（STT）、`say.sh`（TTS）、`camera`、`app`（统一界面） |
| `wechat-ocr/` | 微信入口：OCR + 窗口操作（LuaJIT + C++） |
| `remote.sh` | tmux + opencode 会话/集群管理（大脑可调用的工具之一） |
| `chrome.md` / `rule.md` | 参考文档（Chrome 控制、UTEL 编码） |

---

## 关键约定

1. **运行时禁止引入 Python**。语音识别用 C++ 的 `SenseVoice.cpp`，合成用 `sherpa-onnx + Kokoro`，微信用 LuaJIT + C++。不要新增 `.py` 运行时依赖。
2. **白名单是安全边界**。任何“大脑能执行的操作”都必须是一个 `operator/tools/*.sh`：
   - 新增工具时，必须同步：`operator/tools/<name>.sh`、`operator/AGENTS.md` 的工具表、`operator/opencode.json` 的 `bash` 放行项、`guard.js` 正则（当前限定 `tools/<name>.sh`，一般无需改）。
   - 不要给大脑开放任意 shell、文件读写、网络。
3. **两层 AGENTS.md 别混**：根目录本文件=开发说明；`operator/AGENTS.md`=运行时契约。
4. **不提交大文件**：模型（`*.onnx/*.gguf`）、`build*/`、编译产物已在 `.gitignore`，不要 `git add -f`。
5. **改完 opencode 配置需重启**：`opencode.json`、`guard.js`、`operator/AGENTS.md` 不会被热重载。
6. **第三方素材保留署名**：点阵 UI kit（`operator/tools/dotkit/`，来自 karminski-design-skills）为 **CC BY-NC-SA 4.0**，勿删 `NOTICE.md`/`LICENSE`，仅非商业使用。

---

## 常用命令

```bash
# 大脑
operator/start.sh [--bg]                 # 启停 tmux + opencode(4097)

# 语音（纯 C/C++）
make -C voice/listen                     # 编译麦克风监听
make -C voice/camera                     # 编译摄像头窗口
make -C voice/app                        # 编译统一界面
voice/voice.sh say "文本"                 # 文本→USB 音响
voice/voice.sh listen                    # 麦克风→识别→转发
voice/voice.sh app                       # 统一界面

# 微信
cd wechat-ocr
cmake -S . -B build_lib -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib/cmake"
cmake --build build_lib -j"$(nproc)" --target wechat_ocr_core
luajit bridge.lua                        # 微信监控→转发
```

---

## 自主测试（手机微信 → 大脑 端到端闭环）

用**手机微信**给「文件传输助手」发指令，就能让大脑把整条链路自己跑一遍（无需人在电脑前）：

```
手机微信发 "ai 现在几点"
  → 微信云同步到 PC 微信「文件传输助手」
  → wechat-ocr/bridge.sh 后台读预览(OCR) → 以 [微信输入:文件传输助手] 转发大脑
  → 大脑执行白名单工具 → wechat_send.sh 回复(自动加 "ai助手" 前缀)
  → PC 微信发出 → 手机微信收到
```

前提：PC 微信在线，且 `bridge.sh` 与大脑(`operator/start.sh`)都在跑；手机开 USB 调试。

**用 `operator/tools/phone.sh` 自动操作手机发指令：**

```bash
phone.sh status                 # 确认手机已连接/已授权
phone.sh open com.tencent.mm    # 打开微信
phone.sh screen /tmp/p.png      # 截图自查界面与坐标
phone.sh tap X Y                # 按坐标点击（分辨率见 status）
phone.sh type "ai 现在几点"     # 输入中文（自动切 ADBKeyboard，用完复原）
```

要点 / 坑：

- 预览 OCR 对**浅灰小字**易错：`watcher.read_preview` 已加「灰度 + level 20%,85%」预处理；
  `bridge.to_command` 容忍 `ai` / `ai助手` 及 OCR 变体 `al`/`l`/`1`（`#` 可省）。
- `phone.sh type` 打中文靠临时切到 **ADBKeyboard**（`com.android.adbkeyboard`，需先 `adb install` 一次），用完恢复原输入法；ASCII 可直接 `phone.sh text`。
- bridge 一直「无新指令」时，跑 `WECHAT_ONCE=1 WECHAT_DRY=1 wechat-ocr/bridge.sh` 看它实际读到的预览。
- 手机端发送后，PC 微信若未显示，稍等几秒再轮询（bridge 默认每 10s 一轮）。

> 完整的**测试项清单 + 回归流程**见 [`operator/TESTING.md`](operator/TESTING.md)（新加功能后照它做回归）。

---

## 模型 / 外部依赖位置

| 用途 | 路径 |
|------|------|
| SenseVoice 权重 | `/data/models/sense-voice-small-q4_k.gguf` |
| SenseVoice 程序 | `/opt/SenseVoice.cpp/bin/` |
| Kokoro 模型 | `/data/models/kokoro-multi-lang-v1_0/` |
| sherpa-onnx | `/opt/sherpa-onnx/` |
| 微信 OCR 模型 | `wechat-ocr/models/`（不含在库） |
| ONNX Runtime | `/data/venv/onnxruntime-linux-x64-gpu-1.26.0/` |

---

## 修改清单（新增一个“能力”时）——插件模式

> 工具清单与规则**自动生成**，不再手改 `AGENTS.md`。

1. `operator/plugin.sh new <name>` 生成模板（或手写 `operator/tools/<name>.sh`）；
   在头部写元数据：`# @desc 用途`、`# @usage 用法`、`# @rule 给大脑的规则`（可选）、`# @order N`（规则排序）。
2. 实现脚本（参数固定、stdout 简洁、`exit` 明确）。
3. `operator/plugin.sh index` —— 重新生成 `operator/TOOLS.md`（工具表 + 各工具规则）。
4. 权限：`opencode.json` 已用 `tools/*` 放行、`guard.js` 正则也覆盖，**无需改**。
   如需给大脑**额外**能力开关，才动 `opencode.json`。
5. 必要时在 `operator/tools/` 加配套 `.lua`。
6. 手测脚本 → 重启大脑（`operator/start.sh`，opencode 不热重载）让新 `TOOLS.md` 生效。

`TOOLS.md` 由 `opencode.json` 的 `instructions` 自动加载；`AGENTS.md` 只留来源/回程/示例等散文契约。

---

*文档版本: 4.0 · 更新日期: 2026-10-04*
