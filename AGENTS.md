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

## 注意事项

1. **Slave 不直接通信**：所有协调通过 Master 完成；
2. **忽略心跳消息**：Slave 每 15 分钟收到系统自动心跳，无需回复；
3. **Master 负责分配**：复杂任务由 Master 拆解分配给多个 Slave；
4. **端口冲突**：Slave 端口自动计算（4098 + hash(name) % 1000），请避免手动指定冲突端口。

---

*文档版本: 1.1*
*更新日期: 2026-06-21*
