# WeChat OCR —— 微信机器人消息入口与自动化操作框架

本项目把桌面「小龙虾」微信客户端变成可编程的远程消息入口：自动识别聊天内容、执行操作指令、并把结果回发到微信。通过 **OCR + LLM 视觉识别 + 坐标缓存** 的组合，让脚本能够像人一样「看」到微信界面、点击图标、发送消息/文件/图片，无需破解微信协议，也不依赖官方 API。

> 注：本项目中的「微信」指已替换/集成到桌面的「小龙虾」客户端，无需额外安装官方微信。

---

## 项目意义

在远程协作、自动化运维、家庭服务器等场景下，微信往往是最稳定的消息通道。本项目解决的核心问题是：

- **无协议接入**：不调用微信私有 API，不 hook 进程，纯视觉 + 模拟输入操作客户端。
- **跨网络远程控制**：只要桌面微信在线，就能通过消息触发本地脚本、查询状态、执行命令。
- **低门槛扩展**：上层逻辑用 Lua 编写，几行代码即可实现「收到消息 → 执行动作 → 回复结果」的闭环。
- **Agent 联动**：识别出的消息可进一步转发给 Master Agent，由 Master 拆解任务并分发给合适的 Slave Agent 执行。

---

## 架构

```
远程微信消息
      │
      ▼
┌─────────────────────────────────────────┐
│ 桌面「小龙虾」微信客户端                  │
└─────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────┐
│ 识别与操作层                             │
│  ├─ screenshot.cpp/hpp  截图 + 窗口定位   │
│  ├─ ocr.cpp/hpp         PP-OCRv4 文字识别 │
│  ├─ LLM/VLM 视觉识别     图标语义识别      │
│  └─ ImageMagick 连通域    图标几何检测     │
└─────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────┐
│ FFI 封装层                               │
│  libwechat_ocr_core.so (C++ 动态库)      │
│  ocr_core.lua (LuaJIT FFI 绑定)          │
└─────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────┐
│ 业务逻辑层                               │
│  wechat_robot.lua                       │
│  ├─ init / capture / send / send_file    │
│  ├─ screenshot / search / contacts_search │
│  ├─ click_sidebar / click_icon            │
│  ├─ monitor / recording                   │
│  └─ calibrate_icons / 坐标缓存           │
└─────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────┐
│ 指令执行层                               │
│  系统命令 / Chrome AI 搜索 / Agent 转发    │
└─────────────────────────────────────────┘
```

---

## 已实现功能

### 核心能力

| 功能 | 实现 | 说明 |
|------|------|------|
| 窗口定位 | ✅ | xdotool + 白面板检测，跨桌面支持 |
| 三列结构识别 | ✅ | 时间戳动态定位第三列，自适应窗口大小 |
| 聊天文字识别 | ✅ | PaddleOCR PP-OCRv4，GPU 加速 |
| 区域裁剪 | ✅ | 只识别第三列内容区，排除侧边栏噪音 |
| 指令消息捕获 | ✅ | 监控新消息并回调 |
| 结果回发 | ✅ | 剪贴板粘贴 + 回车发送 |
| 搜索联系人 | ✅ | 点搜索框 → 粘贴关键词 → 回车 |
| 通讯录搜索 | ✅ | 点击通讯录图标 → 搜索 → 回车 |
| 发送文件 | ✅ | 点击文件图标 → 粘贴文件名 → 发送 |
| 发送截图 | ✅ | 点击截图图标 → 框选全屏 → 双击确认 → 发送 |
| 侧边栏导航 | ✅ | 点击第一列图标（聊天/通讯录/收藏/朋友圈等） |
| 持续监控 | ✅ | `monitor()` 轮询检测新消息 |
| 操作录屏 | ✅ | ffmpeg 录制完整操作过程 |

### LLM 视觉识别

| 功能 | 实现 | 说明 |
|------|------|------|
| 图标语义识别 | ✅ | Qwen2.5-VL-3B 识别图标名称（如 Chats/Contacts/Folder/Scissors） |
| 通用图标检测 | ✅ | ImageMagick Canny + 连通域分析，无需模板匹配 |
| 名称-动作映射 | ✅ | `icon_actions.lua` 将 LLM 输出映射到标准操作 |
| 第一列图标 | ✅ | 侧边栏导航图标识别 |
| 第三列工具栏 | ✅ | 底部输入栏图标识别（文件、截图、表情等） |
| 第三列顶部按钮 | ✅ | 通话/菜单按钮识别 |

### 坐标缓存与动态计算

| 功能 | 实现 | 说明 |
|------|------|------|
| 一次性校准 | ✅ | `calibrate_icons.lua` 扫描所有图标并保存相对坐标 |
| 坐标缓存 | ✅ | 结果写入 `~/.wechat_icons.json` |
| 动态计算 | ✅ | 运行时取窗口左上角 + 相对坐标 = 当前绝对坐标 |
| 多区域支持 | ✅ | sidebar / toolbar / top 三区域独立缓存 |
| 自动回退 | ✅ | 无缓存时回退到旧硬编码坐标 |

---

## 坐标缓存机制

传统做法：每次操作都用 OCR 定位或用硬编码偏移，速度慢且不耐窗口移动。

本方案：

1. **一次性校准**：`calibrate_icons.lua` 用 VLM 识别所有图标语义，用 ImageMagick 连通域提取几何位置，生成相对窗口左上角 `(0,0)` 的坐标表。
2. **持久化缓存**：保存到 `~/.wechat_icons.json`：
   ```json
   {
     "window": { "w": 2560, "h": 1440 },
     "sidebar": [
       { "name": "WeChat", "name_cn": "微信", "rel_x": 40, "rel_y": 110, "w": 30, "h": 30 }
     ],
     "toolbar": [
       { "name": "Folder", "name_cn": "发送文件", "rel_x": 600, "rel_y": 1260, "w": 30, "h": 30 }
     ],
     "top": []
   }
   ```
3. **动态计算**：运行时通过 `xdotool getwindowgeometry` 拿到窗口左上角 `(wx, wy)`，目标图标绝对坐标 = `(wx + rel_x, wy + rel_y)`。
4. **稳定复用**：第一列宽度固定、图标相对窗口布局稳定，因此缓存长期有效；窗口移动、切换桌面都不影响。
5. **窗口最大化前置**：所有基于坐标的自动化（`activate()`）执行前会调用 `ensure_maximized()`——
   若窗口未最大化则用 `wmctrl` 最大化（依赖 `wmctrl`，未装则静默跳过），保证缓存所基于的布局一致。

### 坐标自校准（路线，暂未实现）

当前坐标是**一次性静态**校准 + 人工核对试出来的，微信版本/主题/分辨率一变就会错位，且没有点错反馈。
计划升级为**自校验闭环**（暂不实现，记录备查）：

```
① 截图(最大化)
② 检测候选元素：文本 → OCR 直接拿名字+框；图标 → 连通域/模板匹配
③ 生成标注图 → 人工/VLM 核对并纠正命名
④ 写入相对坐标缓存
⑤ 点击验证：点一下 → 截图比对“是否出现预期变化” → 不对就重标
⑥ 运行时若某元素连续点空 → 自动触发一次重标定（drift 自愈）
```

取舍：②③ 省人工（快速重标）；⑤⑥ 抗变化（自我纠错）。按“本地自用、先跑通”的基调，优先级不高，需要时再做。

---

## 快速开始

### 1. 环境准备

```bash
# 依赖
sudo apt install luajit xdotool xclip ffmpeg imagemagick
# 已安装：ONNX Runtime GPU、OpenCV、CUDA 12.x
# 已放置模型：models/ch_PP-OCRv4_det_infer.onnx、models/ch_PP-OCRv4_rec_infer.onnx
# 已放置字典：ppocr_keys_v1.txt
```

### 2. 一次性图标校准

```bash
cd /opt/my-agent/wechat-ocr
export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:/opt/my-agent/joycaption-wrapper
export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/usr/local/lualib/?.so;;"

luajit tests/calibrate_icons.lua
```

校准成功后会生成：
- `~/.wechat_icons.json` —— 坐标缓存
- `~/wechat_icons_annotated.png` —— 标注图，用于人工核对

### 3. 启动监控

#### 3.1 常驻入口（推荐）：`bridge.sh`

后台常驻，把微信新消息转发给大脑（opencode:4097）。每 `WECHAT_POLL_SEC`（默认 10）秒一轮：

1. `import -window` 后台抓微信窗口（**不抢焦点**；窗口被最小化则 `windowmap` 映射出来）；
2. OCR 第二列，对**白名单**（`whitelist.txt`，首个=`文件传输助手`）里的每个会话，读其行**预览文字**（=最新消息）；
3. **不点开会话**；预览**以标签开头**（`ai` / `ai助手`，`#` 可省）**且与上次不同**才当作指令，
   去掉标签后以 `[微信输入:<会话名>] ...` 转发大脑；
4. 大脑回复经 `operator/tools/wechat_send.sh --to <会话名>` 发送，自动加 `ai助手` 前缀。

> 为什么不用未读红点触发：`文件传输助手` 通常一直是当前打开的会话，新消息会被微信**自动已读**（不出红点）。
> 故用「预览变化 + 标签」触发更可靠；`is_self` 用发送日志避免把大脑自己的回复当成新指令。

白名单文件：`wechat-ocr/whitelist.txt`（每行一个会话名，`#` 注释）。可用 `WECHAT_WHITELIST`、`WECHAT_CMD_TAG` 覆盖。

```bash
./bridge.sh                    # 常驻（默认 10s）
WECHAT_POLL_SEC=15 ./bridge.sh  # 调试：15s
WECHAT_ONCE=1 WECHAT_DRY=1 ./bridge.sh   # 只跑一轮、只打印不转发
```

> 前提：桌面微信窗口**保持可见**（可被其它窗口遮挡，但不能最小化），且已登录。

#### 3.2 Lua 直接监控

```bash
./run.sh
```

或直接用 Lua：

```lua
local robot = require("wechat_ocr")
robot.init()
robot.monitor({
    interval_ms = 3000,
    on_message = function(text, cycle)
        print("[新消息]", text)
    end
})
robot.destroy()
```

---

## API 速查

```lua
local robot = require("wechat_robot")

robot.init()                          -- 加载 OCR 模型
robot.set_record(true)                -- 开启录像（默认关闭）

-- 校准与缓存
robot.calibrate_icons()               -- 重新运行一次性校准
robot.clear_calibration()             -- 清空缓存
robot.get_icon_pos("Folder", "toolbar")  -- 查图标绝对坐标
robot.click_icon_rel("Folder", "toolbar") -- 按名称点击图标

-- 消息
local text = robot.capture()          -- 读取当前聊天内容
robot.send("你好")                     -- 发送消息
robot.send_file("/tmp/video.mp4")     -- 发送文件
robot.screenshot()                    -- 发送截图

-- 导航与搜索
robot.search("小王")                  -- 搜索联系人
robot.contacts_search("张三")         -- 通讯录搜索
robot.click_sidebar(2)                -- 点击通讯录（1=聊天 2=通讯录 3=收藏...）

-- 监控
robot.monitor({
    interval_ms = 3000,
    on_message = function(text, cycle) end,
    on_initial = function(text) end,
    on_error   = function(err) end,
})

robot.destroy()                       -- 释放资源
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

```lua
robot.monitor({
    interval_ms = 3000,
    on_message = function(text, cycle)
        if text:match("^@cmd") then
            local cmd = text:sub(5)
            os.execute(cmd .. " > /tmp/result.txt 2>&1")
            local f = io.open("/tmp/result.txt")
            local result = f:read("*a"); f:close()
            robot.send(result:sub(1, 500))
        end
    end
})
```

---

## 微信 ↔ Agent 联动

识别到的消息可以转发给 Master Agent，由 Master 拆解并分发给 Slave Agent 执行：

```lua
local robot = require("wechat_robot")

robot.init()
robot.monitor({
    interval_ms = 3000,
    on_message = function(text, cycle)
        if text:match("^@agent") then
            -- 转发给 Master Agent
            os.execute(string.format(
                "/opt/my-agent/remote.sh send master '%s'",
                text:sub(7):gsub("'", "'\\'''")
            ))
        end
    end
})
```

详见项目根目录 `AGENTS.md`。

---

## 项目结构

```
wechat-ocr/
├── README.md              # 本文档
├── WECHAT_OCR.md          # 技术实现文档
├── wechat_robot.lua       # 统一 API 库（含坐标缓存）
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
│   ├── wechat_monitor.lua     # 监控循环
│   ├── icon_actions.lua       # 图标名称→功能映射
│   └── wechat_ocr/            # 核心模块（与源码同步，仓库内为正本）
│       ├── init.lua           # ocr / wechat_ocr 统一 API
│       ├── chrome.lua         # Chrome 控制
│       └── badge_detect.lua   # 第二列红点检测
│
├── tests/
│   ├── TEST.md                # 测试脚本说明
│   ├── calibrate_icons.lua    # 一次性图标校准
│   ├── test_llm_icons.lua     # VLM 图标识别测试
│   ├── test_first_column.lua  # 侧边栏点击测试
│   └── test_*.lua             # 其他测试脚本
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
| wmctrl | 窗口最大化（EWMH，`ensure_maximized` 用） |
| xclip | 剪贴板操作 |
| ffmpeg | 录屏 |
| ImageMagick | 图标连通域检测 |
| CUDA 12.x | GPU 加速 |
| PaddleOCR PP-OCRv4 | 文字检测+识别模型 |
| Qwen2.5-VL-3B | VLM 图标语义识别 |
| llama.cpp / libjoycaption | VLM 推理接口 |
| 小龙虾（微信客户端） | 远程消息入口 |

---

## 注意事项

1. **坐标缓存**：运行 `calibrate_icons.lua` 后，所有图标操作优先使用 `~/.wechat_icons.json`；仓库内附带的 `wechat-ocr/wechat_icons.json` 仅作为兜底。若窗口缩放或微信布局改变，需重新校准。
2. **第一列宽度固定**：侧边栏图标布局稳定，是缓存可靠的基础。
3. **VLM 速度**：图标语义识别约 5 秒，因此只在一次性校准时使用，运行时不再调用 LLM。
4. **Chrome 控制**：网页交互/读取走 `chrome-devtools` MCP（由 opencode 调用），粗动作（开标签/搜索/截图）可用 `wechat_ocr.chrome`；不得启动新 Chrome 进程，不得用 OCR 识别网页。详见 `../chrome.md`。
5. **后台守护**：生产环境建议用 systemd 或 nohup 运行 `monitor()`。

---

*文档版本: 2.0*
*更新日期: 2026-07-12*
