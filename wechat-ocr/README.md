# WeChat OCR — 微信机器人消息入口

通过 LuaJIT + C++ + ONNX Runtime GPU 实现对桌面「小龙虾」微信客户端的识别、操作和监控，把微信消息变成可执行的指令。

> 注：本项目中的「微信」指已替换/集成到桌面的「小龙虾」客户端，无需额外安装官方微信。

---

## 已实现功能

### 核心

| 功能 | 实现 | 说明 |
|------|------|------|
| 窗口定位 | ✅ | xdotool + 白面板检测，跨桌面支持 |
| 三列结构识别 | ✅ | 时间戳动态定位第三列，自适应窗口大小 |
| 聊天文字识别 | ✅ | PaddleOCR PP-OCRv4，GPU 加速 |
| 区域裁剪 | ✅ | 只识别第三列内容区，排除侧边栏噪音 |
| 指令消息捕获 | ✅ | 监控新消息并回调 |
| 结果回发 | ✅ | 剪贴板粘贴 + 回车发送 |
| Chrome AI 搜索 | ✅ | 地址栏 → Tab → 回车，触发 Google AI 模式 |
| AI 结果复制 | ✅ | Ctrl+A → Ctrl+C 获取 AI 回答 |
| 微信 ↔ AI 互通 | ✅ | 微信发指令 → Chrome AI 搜索 → 结果回微信 |
| 操作录屏 | ✅ | ffmpeg 录制完整操作过程 |
| 文件发送 | ✅ | 点文件图标 → 粘贴文件名 → 回车 |
| 截图发送 | ✅ | 点截图图标 → 框选全屏 → 双击确认 → 发送 |
| 搜索联系人 | ✅ | 点搜索框 → 粘贴关键词 → 回车 |
| 通讯录搜索 | ✅ | 通讯录 → 搜索 → 回车 |
| 侧边栏导航 | ✅ | 点击第一列 7 个图标（聊天/通讯录/收藏/朋友圈等） |
| 持续监控 | ✅ | `monitor()` 轮询检测新消息 |
| 录屏 | ✅ | ffmpeg 全屏录制，可选开启 |
| 图标检测 | ✅ | 全窗口/第三列小图标检测标注 |

### 待完善

| 功能 | 说明 |
|------|------|
| AI 自动回复 | monitor 回调已就绪，需接 LLM |
| 后台守护 | 需 systemd/nohup 部署 |
| 异常重连 | 微信崩溃自动重启 |
| 消息分流 | 识别当前聊天窗口 |

---

## 架构

```
┌─ 消息入口层 ─────────────────────────────┐
│  小龙虾（桌面微信客户端）                  │
└─────────────────────────────────────────┘
      │
      ▼
┌─ 识别层 ─────────────────────────────────┐
│  screenshot.cpp/hpp    截图 + 窗口定位      │
│  ocr.cpp/hpp           PP-OCRv4 文字识别    │
└─────────────────────────────────────────┘
      │
      ▼
┌─ FFI 封装层 ─────────────────────────────┐
│  libwechat_ocr_core.so (C++ 动态库)       │
│  ocr_core.lua (LuaJIT FFI 绑定)           │
└─────────────────────────────────────────┘
      │
      ▼
┌─ 业务逻辑层 ─────────────────────────────┐
│  wechat_robot.lua   (统一 API 库)          │
│  init / capture / send / send_file         │
│  screenshot / search / contacts_search     │
│  click_sidebar / monitor / recording       │
└─────────────────────────────────────────┘
      │
      ▼
┌─ 指令执行层 ─────────────────────────────┐
│  系统命令 / Chrome 搜索 / Agent 转发       │
└─────────────────────────────────────────┘
```

---

## 快速开始

### 1. 启动微信机器人监控

```bash
cd /opt/my-agent/wechat-ocr
./run.sh
```

### 2. 用 Lua 脚本接收并处理指令

```lua
local robot = require("wechat_robot")

robot.init()                          -- 加载 OCR 模型（首次约 3-5 秒）
robot.set_record(true)                -- 可选：开启录像（默认关闭）

-- 搜索联系人
robot.search("小王")

-- 读取用户从微信发来的消息
local text = robot.capture()
print("收到消息：", text)

-- 持续监控：把消息解析为指令并执行
robot.monitor({
    interval_ms = 3000,
    on_message = function(text, cycle)
        print("[新消息]", text)
        -- 示例：以 @cmd 开头的消息作为系统命令执行
        if text:match("^@cmd") then
            local cmd = text:sub(5)
            os.execute(cmd .. " > /tmp/result.txt 2>&1")
            local f = io.open("/tmp/result.txt")
            local result = f:read("*a"); f:close()
            robot.send(result:sub(1, 500))
        end
    end
})

robot.destroy()                       -- 释放资源，自动停止录像
```

---

## 指令消息处理示例

在微信里发送：

```
@cmd ls -la
```

机器人会：
1. OCR 识别出 `@cmd ls -la`
2. 在 `on_message` 回调中解析出命令 `ls -la`
3. 执行命令并把结果发回微信。

---

## 微信 ↔ Google AI 互通流程

```
微信收到消息 "马斯克最新身价"
  ↓
Lua 脚本检测到新消息
  ↓
chrome.ai_search("马斯克最新身价")
  ├─ Chrome 新标签（Ctrl+T）
  ├─ 地址栏粘贴问题（xclip）
  ├─ Tab（移到 AI 模式）
  └─ Return（触发 AI 回答）
  ↓
等待 AI 回答（4 秒）
  ↓
Ctrl+A → Ctrl+C 复制页面内容
  ↓
xclip -o 读取剪贴板
  ↓
微信粘贴结果 → 发送
```

### 测试脚本

```bash
# AI 搜索 + 截图保存
luajit tests/test_ai_search.lua "问题"

# AI 搜索 + 结果发微信
luajit tests/ai_to_wechat.lua
```

### API

```lua
local chrome = require("wechat_ocr.chrome")
chrome.ai_search("问题")     -- AI搜索: 新标签→粘贴→Tab→回车
chrome.screenshot("/tmp/s.png")  -- 截图

-- 获取 AI 回答（Ctrl+A → Ctrl+C → 读剪贴板）
os.execute("xdotool key ctrl+a ctrl+c")
local pipe = io.popen("xclip -selection clipboard -o")
local answer = pipe:read("*a"); pipe:close()
```

---

## 录像功能

```lua
robot.set_record(true)                -- 开启（默认关）
robot.set_record_output("/tmp/demo.mp4")  -- 指定输出路径
-- 之后所有操作都会被录下来
robot.init()
-- ... 各种操作 ...
robot.destroy()  -- 自动停止录像

-- 或手动控制:
robot.start_recording("out.mp4", 15)  -- 录15秒
-- ... 操作 ...
robot.stop_recording()
```

---

## 测试脚本

详见 `tests/TEST.md`：

| 脚本 | 功能 |
|------|------|
| `test_3columns.lua` | 三列结构检测 |
| `test_icons.lua` | 全窗口图标检测 |
| `test_third_icons.lua` | 第三列图标检测 |
| `test_send_file.lua` | 发送文件 |
| `test_screenshot.lua` | 截图发送 |
| `test_search.lua` | 搜索联系人 |
| `test_contacts_search.lua` | 通讯录搜索 |
| `test_first_column.lua` | 第一列图标点击 |
| `wechat_robot.lua` | 统一 API 库 |
| `test_ai_search.lua` | Chrome AI 搜索 |
| `ai_to_wechat.lua` | AI → 微信发送 |

---

## 项目结构

```
wechat-ocr/
├── README.md              # 本文档
├── WECHAT_OCR.md          # 技术实现文档
├── CLAUDE.md              # Chrome 控制强制规则
├── wechat_robot.lua       # 统一 API 库
├── run.lua                # 入口脚本
├── run_ops.lua            # 演示脚本
├── build_final.sh         # 编译 C 库
├── CMakeLists.txt         # CMake 配置
│
├── lib/
│   ├── libwechat_ocr_core.so  # C++ 动态库
│   ├── wechat_ocr_core.h      # C API 头文件
│   └── wechat_ocr_core.cpp    # C API 实现
│
├── src/
│   ├── screenshot.cpp/hpp     # 截图 + 窗口检测
│   └── ocr.cpp/hpp            # OCR 推理封装
│
├── lua/
│   ├── ocr_core.lua           # FFI 绑定
│   └── wechat_monitor.lua     # 监控循环
│
├── tests/
│   ├── TEST.md
│   └── test_*.lua
│
├── models/
│   ├── ch_PP-OCRv4_det_infer.onnx
│   └── ch_PP-OCRv4_rec_infer.onnx
│
└── ppocr_keys_v1.txt        # 中文字典
```

---

## 依赖

| 组件 | 用途 |
|------|------|
| LuaJIT | 脚本语言 |
| ONNX Runtime GPU | 深度学习推理 |
| OpenCV | 图像处理 |
| xdotool | 窗口/鼠标/键盘控制 |
| xclip | 剪贴板操作 |
| ffmpeg | 录屏 |
| CUDA 12.x | GPU 加速 |
| PaddleOCR PP-OCRv4 | 文字检测+识别模型 |
| 小龙虾（微信客户端） | 远程消息入口 |

---

## Chrome 浏览器控制规则（必须遵守）

1. **用 Lua** — 通过 `require("wechat_ocr.chrome")` 调用，不得使用 Node.js/其他语言
2. **不打开新浏览器** — 只能操作现有 Chrome 窗口，不得启动新 Chrome 进程
3. **新开空白标签** — 用 `chrome.new_tab()`（Ctrl+T），不要打开具体网址，除非用户明确要求
4. **禁止 OCR 识别浏览器网页** — 不得使用 PaddleOCR 或任何 OCR 方式识别浏览器页面内容

```lua
local chrome = require("wechat_ocr.chrome")
chrome.new_tab()          -- ✅ 新开空白标签
chrome.open("网址")        -- ✅ 新标签打开网址
chrome.search("关键词")    -- ✅ 新标签 Google 搜索
chrome.ai_search("问题")   -- ✅ AI 模式搜索
chrome.screenshot()       -- ✅ 截图
```

详见 [chrome.md](../chrome.md) 和 [CLAUDE.md](CLAUDE.md)。

---

*文档版本: 1.1*
*更新日期: 2026-06-21*
