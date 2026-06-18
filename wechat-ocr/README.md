# WeChat OCR — 桌面微信自动化操作框架

通过 LuaJIT + C++ + ONNX Runtime GPU 实现对桌面微信的识别、操作和录屏。

## 已实现功能

### 核心

| 功能 | 实现 | 说明 |
|------|------|------|
| 窗口定位 | ✅ | xdotool + 白面板检测，跨桌面支持 |
| 三列结构识别 | ✅ | 时间戳动态定位第三列，自适应窗口大小 |
| 聊天文字识别 | ✅ | PaddleOCR PP-OCRv4，GPU 加速 |
| 区域裁剪 | ✅ | 只识别第三列内容区，排除侧边栏噪音 |
| 逐字输入发送 | ✅ | 剪切板逐字粘贴 + 随机延时 + 回车 |
| 文件发送 | ✅ | 点文件图标 → 粘贴文件名 → 回车 |
| 截图发送 | ✅ | 点截图图标 → 框选全屏 → 双击确认 → 发送 |
| 搜索联系人 | ✅ | 点搜索框 → 粘贴关键词 → 回车 |
| 通讯录搜索 | ✅ | 通讯录 → 搜索 → 回车 |
| 侧边栏导航 | ✅ | 点击第一列7个图标（聊天/通讯录/收藏/朋友圈等）|
| 持续监控 | ✅ | monitor() 轮询检测新消息 |
| 录屏 | ✅ | ffmpeg 全屏录制，可选开启 |
| 图标检测 | ✅ | 全窗口/第三列小图标检测标注 |

### 待完善

| 功能 | 说明 |
|------|------|
| AI 自动回复 | monitor 回调已就绪，需接 LLM |
| 后台守护 | 需 systemd/nohup 部署 |
| 异常重连 | 微信崩溃自动重启 |
| 消息分流 | 识别当前聊天窗口 |

## 架构

```
┌─ 应用层 ──────────────────────────────┐
│  wechat_robot.lua   (统一API)          │
│  init / capture / send / send_file    │
│  screenshot / search / contacts_search │
│  click_sidebar / monitor / recording   │
├───────────────────────────────────────┤
│  wechat_ocr/init.lua (OCR引擎封装)      │
│  open / send / capture / monitor       │
├─ FFI ─────────────────────────────────┤
│  libwechat_ocr_core.so (C++ 动态库)    │
│  X11截图+窗口检测+ONNX Runtime推理      │
├─ 模型 ────────────────────────────────┤
│  PaddleOCR PP-OCRv4 (det+rec) ONNX    │
└───────────────────────────────────────┘
```

## 快速开始

```lua
local robot = require("wechat_robot")

robot.init()                          -- 加载OCR模型（首次约3-5秒）
robot.set_record(true)                -- 可选：开启录像（默认关闭）

robot.search("小王")                  -- 搜索联系人
robot.send("端午安康！")               -- 逐字输入发送
robot.send_file("photo.png")          -- 发文件
robot.screenshot()                    -- 截图发送
robot.contacts_search("张三")         -- 通讯录搜索
robot.click_sidebar(1)                -- 点侧边栏第1个图标

local text = robot.capture()          -- 读取聊天内容

-- 持续监控
robot.monitor({
    interval_ms = 3000,
    on_message = function(text)
        print("[新消息]", text)
    end
})

robot.destroy()                       -- 释放资源，自动停止录像
```

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
| `wechat_robot.lua` | 统一API库 |

## 项目结构

```
wechat-ocr/
├── wechat_robot.lua          ← 统一API库
├── run.lua                   ← 启动入口
├── build_final.sh            ← 编译C库
├── CMakeLists.txt
├── lib/
│   ├── libwechat_ocr_core.so ← C++动态库
│   ├── wechat_ocr_core.h     ← C API
│   └── wechat_ocr_core.cpp   ← C API实现
├── src/
│   ├── screenshot.cpp/hpp    ← 截图+窗口检测
│   └── ocr.cpp/hpp           ← OCR推理封装
├── lua/
│   └── wechat_monitor.lua
├── tests/
│   ├── TEST.md
│   ├── test_*.lua            ← 测试脚本
│   ├── find_*.py             ← 图标检测
│   └── mark_columns.py       ← 三列标注
├── models/
│   ├── ch_PP-OCRv4_det_infer.onnx
│   └── ch_PP-OCRv4_rec_infer.onnx
├── ppocr_keys_v1.txt         ← 中文字典
└── run.sh                    ← 环境变量配置
```

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
