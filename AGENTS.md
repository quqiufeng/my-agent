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

## 修改清单（新增一个“能力”时）

1. 写 `operator/tools/<name>.sh`（参数固定、stdout 简洁、`exit` 明确）。
2. 在 `operator/AGENTS.md` 表格加一行（用途 + 用法）。
3. 在 `operator/opencode.json` 的 `bash` 里放行对应命令形态。
4. 必要时在 `operator/tools/` 里加配套 `.lua`。
5. 本地手测脚本可用，再重启 opencode 验证大脑能调用。

---

*文档版本: 4.0 · 更新日期: 2026-10-04*
