# WeChat OCR 测试脚本

本目录包含「微信机器人」框架的各类测试脚本，用于验证截图、OCR、窗口定位、消息发送、Chrome 搜索等能力。

> **状态说明**
> - ✅ 已验证：曾经在对应环境下跑通过，但因微信版本、分辨率、主题变化可能仍需重测。
> - ⚠️ 未验证：已编写但尚未在目标环境充分测试。
> - 所有脚本都需要先完成 [环境准备](#环境准备)。

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
| `test_3columns.lua` | 检测微信窗口三列结构，输出分界位置和标注图 | ✅ 已验证 | `luajit tests/test_3columns.lua` |
| `test_first_icons.lua` | 第一列 7 个图标检测，输出标注图 | ✅ 已验证 | `luajit tests/test_first_icons.lua` |
| `test_first_column.lua` | 依次点击第一列 7 个图标 | ⚠️ 未验证 | `luajit tests/test_first_column.lua` |
| `test_third_icons.lua` | 第三列工具栏图标检测 | ✅ 已验证 | `luajit tests/test_third_icons.lua` |

**输出文件**：
- `~/wechat_3cols_*.png`
- `~/wechat_first_icons_*.png`
- `~/wechat_third_icons_*.png`

---

### 2. 消息交互操作

| 脚本 | 功能 | 状态 | 用法 |
|------|------|------|------|
| `test_search.lua` | 搜索联系人，可选点第一个结果并发送消息 | ⚠️ 未验证 | `luajit tests/test_search.lua "小王"` 或 `luajit tests/test_search.lua "小王" "你好！"` |
| `test_contacts_search.lua` | 通讯录搜索 | ⚠️ 未验证 | `luajit tests/test_contacts_search.lua "小王"` |
| `test_send_file.lua` | 点文件图标 → 粘贴文件名 → 发送 | ⚠️ 未验证 | `luajit tests/test_send_file.lua ~/video.mp4` |
| `test_screenshot.lua` | 点截图图标 → 框选全屏 → 发送 | ⚠️ 未验证 | `luajit tests/test_screenshot.lua` |

搜索框默认位置：`(wx+180, wy+50)`。

---

### 3. 未读消息与列表检测

| 脚本 | 功能 | 状态 | 用法 |
|------|------|------|------|
| `test_unread_detect.lua` | OCR 全窗口找第二列数字未读数 | ⚠️ 未验证 | `luajit tests/test_unread_detect.lua` |
| `test_two_lines.lua` | 第二列聊天条目等距标注 + 自动点击 | ⚠️ 未验证 | `luajit tests/test_two_lines.lua` |
| `test_avatar_badges.lua` | 头像红点/红底白字数字检测 | ⚠️ 未验证 | `luajit tests/test_avatar_badges.lua` |
| `test_avatars.lua` | 第二列头像 OCR 检测 | ⚠️ 未验证 | `luajit tests/test_avatars.lua` |

---

### 4. Chrome AI 搜索

| 脚本 | 功能 | 状态 | 用法 |
|------|------|------|------|
| `test_ai_search.lua` | Chrome AI 搜索 → 复制结果 → 输出 | ⚠️ 未验证 | `luajit tests/test_ai_search.lua "马斯克最新身价多少"` |
| `ai_to_wechat.lua` | Chrome AI 搜索 → OCR 读结果 → 微信发送 | ⚠️ 未验证 | `luajit tests/ai_to_wechat.lua` |
| `google_ai_qa.lua` | 新标签 → 输入问题 → 截图 + OCR 读结果 | ⚠️ 未验证 | `luajit tests/google_ai_qa.lua` |
| `google_ai_test.lua` | 打开 Google → 输入问题 → 点 AI 模式按钮 → 截图 | ⚠️ 未验证 | `luajit tests/google_ai_test.lua` |
| `test_open_chrome.lua` | 启动 Chrome | ⚠️ 未验证 | `luajit tests/test_open_chrome.lua` |
| `chrome_bridge.lua` | 通过 JSON-RPC 与 Chrome DevTools MCP 交互 | ⚠️ 未验证 | `luajit tests/chrome_bridge.lua "打开 https://example.com 并截图"` |

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

1. **`google_ai_qa.lua` 使用了未文档化的 API**：
   - 调用 `chrome.type(...)`，但 `chrome.md` 中未定义该接口。
   - 需要确认 `wechat_ocr.chrome` 模块是否支持，或用 `xclip + xdotool` 替代。

2. **`news_execute.lua` 依赖缺失模块**：
   - 依赖 `wechat_ocr.badge_detect`，当前项目目录中未找到该模块。

3. **`chrome_bridge.lua` 未读取响应**：
   - 只发送 JSON-RPC 请求，未读取 MCP 服务器返回。

4. **坐标硬编码**：
   - 多数脚本假设 2560×1440 分辨率、100% 缩放、固定微信布局。
   - 更换分辨率或微信版本后可能需要调整偏移量。

5. **状态验证 disclaimer**：
   - 标记为 ✅ 的脚本仅代表曾经在特定环境跑通，不保证当前环境一定可用。

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
├── test_contacts_search.lua    # 通讯录搜索
├── test_unread_detect.lua      # 未读数字检测（旧版）
├── test_two_lines.lua          # 第二列条目+自动点击
├── test_avatar_badges.lua      # 头像红点检测
├── test_avatars.lua            # 头像 OCR 检测
├── test_ai_search.lua          # Chrome AI 搜索
├── test_open_chrome.lua        # 打开 Chrome
├── google_ai_qa.lua            # Google AI 问答
├── google_ai_test.lua          # Google AI 测试
├── ai_to_wechat.lua            # AI → 微信发送
├── monitor.lua                 # 未读监控（Lua版）
├── news_execute.lua            # 文件传输助手自动回复
├── chrome_bridge.lua           # Chrome DevTools MCP 桥
└── monitor.c                   # 未读监控 C 源码
```

---

*更新日期: 2026-06-21*
*状态: 已整理，多数脚本待验证*
