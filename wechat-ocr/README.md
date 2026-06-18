# WeChat OCR — 桌面微信识别 + 操作框架

## ⚠️ 开发状态

**当前阶段：基础能力建设，尚未完成机器人级功能。**

| 功能 | 状态 | 说明 |
|------|------|------|
| 窗口定位 | ✅ 完成 | 白面板检测 + 跨桌面切换 |
| 文字识别 (OCR) | ✅ 完成 | PaddleOCR PP-OCRv4，GPU 加速 |
| 区域裁剪 | ✅ 完成 | 跳过图标/列表/标题/输入框，只读内容区 |
| 点击图标开微信 | ✅ 完成 | 找底部绿色图标 → 点击 |
| 逐字输入发送 | ✅ 完成 | 剪切板逐字粘贴 + 随机延时 + 回车 |
| OCR 读取聊天 | ✅ 完成 | 返回纯文本，按 Y 排序 |
| 录屏 | ✅ 完成 | ffmpeg 自动定位微信区域录制 |
| 守护进程 | ❌ 待做 | systemd/nohup 后台驻留 |
| 消息分流（多群） | ❌ 待做 | 识别当前聊天窗口 |
| AI 回复对接 | ❌ 待做 | 调用 LLM API |
| 异常重连 | ❌ 待做 | 微信崩溃自动重启 |
| 日志系统 | ❌ 待做 | 操作记录 + 消息存档 |
| 配置文件 | ❌ 待做 | 回复规则/AI 接口配置 |

## 概述

通过 LuaJIT 调用 C++ OCR 引擎，实现对桌面微信的：
- **定位** — 全屏截图 → 白面板检测 → 三区域识别 → 锁定内容区
- **识别** — ONNX Runtime GPU + PaddleOCR → 提取聊天文字
- **操作** — xdotool 模拟点击 + 剪切板逐字粘贴 + 回车发送
- **录屏** — 自动获取微信位置 → ffmpeg 定点录制 → VLC 回放

## 架构

```
┌─ Lua 层 (逻辑) ─────────────────────────────┐
│  wechat_ocr/init.lua                         │
│  open() / send() / capture() / monitor()     │
│  start_recording() / stop_recording()        │
├─ FFI ───────────────────────────────────────┤
│  libwechat_ocr_core.so (C++ 动态库)           │
│  X11截图 + 白面板检测 + ONNX Runtime 推理     │
├─ 模型 ──────────────────────────────────────┤
│  PaddleOCR PP-OCRv4 (det+rec) → ONNX 格式    │
└──────────────────────────────────────────────┘
```

## 完整流程一键脚本

```bash
cd /opt/my-agent/wechat-ocr

# 发送默认消息，录15秒
bash wechat_send_and_record.sh

# 发送自定义消息，默认15秒
bash wechat_send_and_record.sh "你好，在吗？"

# 自定义消息 + 录屏时长
bash wechat_send_and_record.sh "今天天气不错" 20
```

脚本执行内容：

```
[1/5] 开始录屏               ffmpeg 后台录全屏
[2/5] 加载 OCR 模型          ONNX Runtime + PaddleOCR
      1. 点微信图标           ocr.open() 找底部绿图标
      2. 输入消息             ocr.send() 逐字中文+回车
      3. 读取验证             ocr.capture() OCR 读回
[3/5] 等待录屏结束           等待 ffmpeg 录完
[4/5] 播放录像               VLC 打开回放
[5/5] 完成
```

## Lua 模块 API

```lua
local ocr = require("wechat_ocr")

-- 初始化
ocr.init("det_model.onnx", "rec_model.onnx", "dict.txt")

-- 打开微信（找底部绿色图标点击）
ocr.open(wait_ms)           -- wait_ms: 等待窗口出现(默认2000ms)

-- 发送消息（逐字粘贴+回车，模拟人输入）
ocr.send("你好")            -- 自动随机延时 80-250ms

-- 读取聊天内容（只读第三区域，跳过图标和侧边栏）
local text = ocr.capture()  -- 返回字符串，每行一条消息

-- 持续监控新消息
ocr.monitor({
    on_message = function(text, cycle)
        print("[新消息]", text)
    end
})

-- 录屏（自动定位微信区域）
ocr.start_recording("output.mp4", 10)   -- 10fps
ocr.stop_recording()
```

## 手动分步操作

```bash
# 1. 设置环境变量
export LD_LIBRARY_PATH="/opt/my-agent/wechat-ocr/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib"
export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/usr/local/lualib/?.so;;"

# 2. 运行 Lua 脚本
cd /opt/my-agent/wechat-ocr
/usr/local/bin/luajit -e '
local ocr = require("wechat_ocr")
ocr.init("models/ch_PP-OCRv4_det_infer.onnx",
         "models/ch_PP-OCRv4_rec_infer.onnx",
         "ppocr_keys_v1.txt")
ocr.open()
ocr.send("测试消息")
print(ocr.capture())
ocr.destroy()
'
```

## 微信窗口识别原理

```
全屏截图 → 白面板检测 → 定位微信窗口
  → 裁剪第三区域（跳过图标栏+侧边栏+标题栏+输入框）
  → OCR 识别纯聊天内容

  区域1: 图标功能区     (0-2%)   绿/灰图标
  区域2: 列表显示区域   (10-28%) 聊天列表/功能列表
  区域3: 内容展示区     (28-90%) 聊天消息/公众号文章等
```

## 发送原理（绕过输入法）

```
ocr.send("你好")
  → 逐字遍历 UTF-8 字符
  → 每字: xclip → Ctrl+V 粘贴（绕过中文输入法）
  → 随机延时 80-250ms（模拟人输入）
  → 全部输入完后回车发送
```

## 录屏原理

```
ocr.start_recording()
  → ocr.capture_raw() 获取微信窗口位置 (x,y,w,h)
  → ffmpeg -f x11grab -s WxH -i :0.0+X+Y ...
  → 只录微信区域，不录全屏
```

## 项目文件结构

```
wechat-ocr/
├── wechat_send_and_record.sh   ← 一键发送+录屏脚本
├── README.md                   ← 本文件
├── WECHAT_OCR.md               ← 技术架构文档
├── run_ops.lua                 ← 微信操作 Lua 脚本
│
├── lib/
│   ├── libwechat_ocr_core.so   ← C++ 动态库
│   ├── wechat_ocr_core.h       ← C API 头文件
│   └── wechat_ocr_core.cpp     ← C API 实现
│
├── src/
│   ├── screenshot.cpp/hpp      ← 截图 + 窗口检测
│   └── ocr.cpp/hpp             ← OCR 推理封装
│
├── models/
│   ├── ch_PP-OCRv4_det_infer.onnx  ← 文字检测模型
│   └── ch_PP-OCRv4_rec_infer.onnx  ← 文字识别模型
│
├── ppocr_keys_v1.txt           ← 中文字典 (6623字符)
│
└── /usr/local/lualib/wechat_ocr/init.lua  ← Lua 模块
```

## 依赖

| 组件 | 用途 | 安装 |
|------|------|------|
| LuaJIT | 脚本语言 | `/usr/local/bin/luajit` |
| ONNX Runtime GPU | 推理引擎 | `/data/venv/onnxruntime-...` |
| OpenCV | 图像处理 | `apt install libopencv-dev` |
| X11/XShm | 截图 | 系统自带 |
| xdotool | 窗口/鼠标/键盘控制 | `apt install xdotool` |
| xclip | 剪切板操作 | `apt install xclip` |
| ffmpeg | 录屏 | `apt install ffmpeg` |
| VLC | 播放录像 | `apt install vlc` |
