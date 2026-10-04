# WeChat OCR 测试脚本

本目录包含「微信机器人」框架的各类测试脚本，用于验证截图、OCR、窗口定位、消息发送、Chrome 搜索等能力。

> **状态说明**
> - ✅ 统一 API（`wechat_robot.lua`）的搜索/发送/文件/截图/未读检测流程已在当前环境验证。
> - ⚠️ 其余单个测试脚本部分已验证、部分未验证，使用前建议重新运行确认。
> - 所有脚本都需要先完成 [环境准备](#环境准备)。

---

## LLM 图标识别（VLM）

基于 Qwen2.5-VL-3B 的图标语义识别 pipeline。

### 模型路径

```bash
/data/models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf       # LLM 模型 (1.8GB)
/data/models/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf  # 视觉投影 (806MB)
```

### 启动命令

```bash
cd /opt/my-agent/wechat-ocr

# 基础环境
export LD_LIBRARY_PATH="./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:/opt/my-agent/joycaption-wrapper:/opt/llama.cpp/build/bin"

# 扫描并逐个点击所有侧边栏图标
./tests/run_click_all_icons.sh

# 独立 VLM 测试
./tests/run_llm_icons.sh
```

---

## 环境准备

```bash
cd /opt/my-agent/wechat-ocr

export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib
export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/usr/local/lualib/?.so;;"
```

或直接用：

```bash
./run.sh
```

**前置条件**：
- 桌面已登录「小龙虾」微信客户端
- 已安装 `luajit`、`xdotool`、`xclip`、`ffmpeg`、`imagemagick`
- 已编译 `lib/libwechat_ocr_core.so`
- 已放置 OCR 模型：`models/ch_PP-OCRv4_det_infer.onnx`、`models/ch_PP-OCRv4_rec_infer.onnx`
- 推荐屏幕分辨率 2560×1440，窗口缩放 100%

---

## 测试脚本一览

### 1. 窗口结构检测

| 脚本 | 功能 | 状态 | 用法 |
|------|------|------|------|
| `test_3columns.lua` | 检测微信窗口三列结构，输出分界位置和标注图 | ✅ 已验证（全屏+非全屏） | `luajit tests/test_3columns.lua` |
| `test_first_icons.lua` | 第一列图标检测（Canny边缘+动态背景色），输出标注图 | ✅ 已验证 | `luajit tests/test_first_icons.lua` |
| `test_first_column.lua` | 依次点击第一列 7 个图标 | ✅ 已验证 | `luajit tests/test_first_column.lua` |
| `test_third_icons.lua` | 第三列工具栏图标检测（x≥525） | ✅ 已验证 | `luajit tests/test_third_icons.lua` |
| `test_toolbar_labels.lua` | 第三栏小工具图标 VLM 语义识别（底部格式栏） | ✅ 已验证 | `luajit tests/test_toolbar_labels.lua` |

**输出文件**：
- `~/wechat_3cols_*.png`
- `~/wechat_first_icons_*.png`
- `~/wechat_third_icons_*.png`

---

### 2. 消息交互操作

| 脚本 | 功能 | 状态 | 用法 |
|------|------|------|------|
| `test_search.lua` | 搜索联系人→回车开聊天→输入消息→回车发送 | ✅ 已验证 | `luajit tests/test_search.lua "丰" "你好"` |

| `test_send_file.lua` | 点文件图标 → 粘贴文件名 → 发送 | ✅ 已验证 | `luajit tests/test_send_file.lua ~/video.mp4` |
| `test_screenshot.lua` | 搜索 → 截图→ 发送（缓存坐标） | ✅ 已验证 | `luajit tests/test_screenshot.lua [关键词]` |

搜索框默认位置：`(wx+180, wy+50)`。

---

### 3. 未读消息与列表检测

| 脚本 | 功能 | 状态 | 用法 |
|------|------|------|------|
| `test_unread_detect.lua` | 第二列红色未读检测（红圈检测） | ✅ 已验证 | `luajit tests/test_unread_detect.lua` |

---

---

### 5. 监控与自动回复

| 脚本 | 功能 | 状态 | 用法 |
|------|------|------|------|
| `monitor.lua` | Lua 版未读红点监控 | ⚠️ 未验证 | `luajit tests/monitor.lua` / `luajit tests/monitor.lua --once` |
| `news_execute.lua` | 文件传输助手未读 → 读取 → 自动回复 | ⚠️ 未验证 | `luajit tests/news_execute.lua` |
| `monitor.c` | C 版未读红点监控守护进程 | ⚠️ 未验证 | `gcc -O2 -o monitor monitor.c && ./monitor --once` |

---

## 统一 API 速查

日常开发建议直接使用 `wechat_robot.lua`：

```lua
local robot = require("wechat_robot")
robot.init()
robot.send("你好")
robot.send_file("a.mp4")
robot.screenshot()
robot.search("小王")
robot.contacts_search("张三")
robot.click_sidebar(3)
robot.capture()
robot.monitor({on_message=fn})
robot.set_record(true)  -- 开启录像
robot.destroy()
```

详见 `../wechat_robot.lua`。

---

## 已知问题

1. **Chrome API 已补齐**：
   - `chrome.type(...)` / `chrome.open(...)` / `chrome.search(...)` 均已在 `lua/wechat_ocr/chrome.lua` 中实现。
   - 规则仍以 `../CLAUDE.md` 为准（不新开浏览器、不用 OCR 识别网页）。

2. **`badge_detect` 模块已纳入仓库**：
   - `wechat_ocr.badge_detect` 现位于 `lua/wechat_ocr/badge_detect.lua`，`news_execute.lua` 可直接使用。

3. **坐标硬编码（已部分修复）**：
   - `wechat_robot.lua` 中录屏/截图/未读列宽已改为按窗口/屏幕尺寸动态计算；个别测试脚本仍假设 2560×1440。

4. **测试状态不一致**：
   - 核心库流程已验证；单个测试脚本的状态以本节“测试脚本一览”为准，改动后请重新运行。

---

## 文件清单

```
tests/
├── TEST.md                     # 本文档
├── test_3columns.lua           # 三列结构检测
├── test_first_icons.lua        # 第一列图标检测
├── test_first_column.lua       # 第一列图标依次点击
├── test_third_icons.lua        # 第三列图标检测
├── test_send_file.lua          # 发送文件
├── test_screenshot.lua         # 截图发送
├── test_search.lua             # 搜索联系人
├── test_toolbar_labels.lua     # 第三栏小工具图标 VLM 识别

├── test_unread_detect.lua      # 未读数字检测（旧版）

├── google_ai_qa.lua            # Google AI 问答
├── ai_to_wechat.lua            # AI → 微信发送
├── monitor.lua                 # 未读监控（Lua版）
├── news_execute.lua            # 文件传输助手自动回复
└── monitor.c                   # 未读监控 C 源码
```

---

*更新日期: 2026-10-04*
*状态: 核心库流程已验证；其余脚本见上表状态*
