# Agent 管理 - Master-Slave 架构

## 在项目中的角色

本项目把微信（小龙虾）作为远程消息入口，OCR 识别出的消息可以进一步**转发给 Master Agent**，由 Master 拆解并分配给合适的 Slave Agent 执行。Master-Slave 架构负责「指令执行层」的调度，而不是微信消息采集层。

```
远程微信消息
      │
      ▼
┌─────────────┐
│ WeChat OCR  │  识别消息文本
└─────────────┘
      │
      ▼
   Master (4097)  ──▶ 分析任务、选择 Slave
      │
      ├──▶ Slave-1 (coder)        写代码/执行脚本
      ├──▶ Slave-2 (reviewer)      审查/汇总
      └──▶ Slave-N (...)           其他专用 Agent
```

## 核心原则

- 所有任务由 **Master** 统一分配；
- **Slave** 只负责执行，不直接通信；
- Master 通过心跳监控所有 Slave 状态。

## 角色定义

| 角色 | 名称 | 端口 | 职责 |
|------|------|------|------|
| **Master** | master | 4097 | 任务分配、Slave 管理、状态监控 |
| **Slave** | coder, reviewer... | 4098+ | 接收任务、执行工作、汇报结果 |

Slave 端口计算方式：

```bash
port = 4098 + (md5(name) % 1000)
```

## 快速开始

### 1. 启动 Master

```bash
./agent.sh start master
```

### 2. 启动 Slave

```bash
# 启动 coder
./agent.sh start coder

# 启动 reviewer
./agent.sh start reviewer
```

### 3. 查看状态

```bash
./agent.sh status
```

### 4. 发送任务

```bash
# 直接发给 Slave
./agent.sh send coder "写一个 Python 爬虫"

# 发给 Master 分配
./agent.sh send master "需要一个爬虫，请分配给合适的 Slave"
```

## 与微信机器人联动

在 Lua 监控回调中，可以把识别到的消息提交给 Master：

```lua
local robot = require("wechat_robot")
local cmd = require("wechat_ocr.cmd_bridge")  -- 示例模块

robot.init()
robot.monitor({
    interval_ms = 3000,
    on_message = function(text)
        -- 判断是否为 Agent 任务指令
        if text:match("^@agent") then
            cmd.send_to_master(text:sub(7))
        end
    end
})
robot.destroy()
```

## 心跳机制

### Master 自心跳（每 25 分钟）
- Master 给自己发 keepalive；
- 防止 Master 无故停机；
- 检查是否有待分配的任务。

### Slave 状态汇报（每 15 分钟）
- Slave 向 Master 汇报状态；
- 消息格式：`[Agent心跳] Agent: 'xxx' 运行正常...`；
- Master 收到后更新 Slave 状态表；
- 连续 3 次健康检查失败，Master 会自动重启该 Slave。

## 常用命令

```bash
# 启动
./agent.sh start <name>

# 停止
./agent.sh stop <name>

# 查看状态
./agent.sh status

# 发送任务
./agent.sh send <name> <instruction>

# 进入查看
./agent.sh attach <name>

# 销毁
./agent.sh destroy <name>
```

## 图标识别（通用技术）

WeChat 侧边栏图标识别使用完全通用的 pipeline，**不依赖微信特定特征**，可直接复用于任何 GUI 应用的图标检测与语义识别。

### 流程

```
屏幕截图 → ImageMagick 检测 → 裁图标区域 → VLM 语义识别 → 名称-位置-动作映射
```

### 步骤详解

**1. 截图（通用）**
```bash
import -window root -crop WxH+X+Y /tmp/screen.png
```
任何桌面应用的窗口截图，无微信绑定。

**2. ImageMagick 图标检测（通用）**
```bash
# 自动检测图标列宽（投影法）
convert screen.png -crop 120xH+0+0 -colorspace gray \
  -fx 'abs(u - bg/255) > 0.04' -scale 1xH! -scale 120xH! \
  txt:- | awk '/#FFFFFF/{print $1}' | sort -rn | head -1

# Connected Components 提取图标
convert screen.png -crop WxH+0+0 -colorspace gray \
  -canny 0x1+5%+10% -negate \
  -define connected-components:verbose=true \
  -connected-components 4 /dev/null
```
Canny 边缘检测 + 连通域分析，提取所有独立视觉元素。自动过滤过小/过大/畸形组件。**不需要图标库、不需要模板匹配、不需要 OCR**。

**3. VLM 语义识别（通用）**
```cpp
// 裁出图标列 → Qwen2.5-VL-3B 识别
std::string prompt = "List each icon from top to bottom. "
                     "Give: number, name, brief description.";
```
通过 llama.cpp mtmd 接口加载视觉语言模型（Qwen2.5-VL-3B），对图标列截图直接做语义理解。零样本识别，**无需训练数据**，换任何应用的图标都能识别。

**4. 名称-动作映射（通用）**
```lua
-- icon_actions.lua
local map = {
  Chats   = { name_cn = "聊天",   action = "open_chats" },
  Moments = { name_cn = "朋友圈", action = "open_moments" },
}
```
将 VLM 输出的英文/中文图标名称映射到具体操作函数。**只需更新映射表即可适配新应用**。

### 为什么是通用的

| 组件 | 通用性 |
|------|--------|
| 截图 | `import` / `xdotool`，任何 X11 窗口 |
| 图标检测 | Connected Components + 几何过滤，不依赖特定 UI 布局 |
| 语义识别 | VLM 零样本，换应用只需改 prompt 和映射表 |
| 点击执行 | `xdotool mousemove + click`，通用鼠标操作 |
| 模型 | Qwen2.5-VL-3B，可替换为任何 MTMD 兼容的 VLM |

### 已知限制

1. **速度**：VLM 推理约 5s，不适合高频实时交互
2. **LLM 幻觉**：高 token 限制下会重复已识别图标（通过限制 128 token 解决）
3. **GPU 依赖**：CPU 推理极慢（>30s），需至少 4GB VRAM

### 相关文件

| 文件 | 作用 |
|------|------|
| `wechat-ocr/wechat_robot.lua` | 集成 `scan_icons()`/`click_icon()` API |
| `wechat-ocr/lua/icon_actions.lua` | 图标名称→功能映射表 |
| `wechat-ocr/tests/test_llm_icons.lua` | 独立测试脚本 |
| `joycaption-wrapper/joycaption_wrapper.cpp` | VLM C 推理接口 |
| `joycaption-wrapper/libjoycaption.so` | 编译产物 |

## 注意事项

1. **Slave 不直接通信**：所有协调通过 Master 完成；
2. **忽略心跳消息**：Slave 每 15 分钟收到系统自动心跳，无需回复；
3. **Master 负责分配**：复杂任务由 Master 拆解分配给多个 Slave；
4. **端口冲突**：Slave 端口自动计算（4098 + hash(name) % 1000），请避免手动指定冲突端口。

---

*文档版本: 1.1*
*更新日期: 2026-06-21*
