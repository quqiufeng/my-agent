# 多 Agent 协作方案设计

## 概述

通过多个专门的 Agent 协作完成复杂任务，类似软件开发团队的协作模式。

## 核心概念

### 角色定义

| 角色 | 职责 | 典型名称 |
|------|------|---------|
| **Master** | 任务分解、协调、决策 | master |
| **Coder** | 代码编写、调试 | coder, frontend, backend |
| **Reviewer** | 代码审查、质量把控 | reviewer |
| **DevOps** | 部署、运维、脚本 | devops |
| **Analyst** | 数据分析、报告 | analyst |

### 端口分配规则

```
master:   4097
agent-1:  4098 + hash(name) % 1000
```

## 协作模式

### 模式一：流水线 (Pipeline)

任务按顺序流经多个 Agent：

```
用户 → Master(分解) → Coder(编码) → Reviewer(审查) → DevOps(部署)
```

**适用场景**: 软件开发、文档编写

### 模式二：并行 (Parallel)

Master 将任务拆分为子任务，多个 Agent 同时执行：

```
         ┌→ Coder-A (前端)
用户 → Master ─┼→ Coder-B (后端)
         └→ Analyst (数据)
         
         ← 汇总结果 ←
```

**适用场景**: 数据并行处理、多模块开发

### 模式三：讨论 (Discussion)

多个 Agent 对同一个问题进行讨论，最终由 Master 决策：

```
问题 → Coder(方案A) ─┐
       Reviewer(方案B) ┼→ Master(决策) → 执行
       Analyst(方案C) ─┘
```

**适用场景**: 架构设计、技术选型

## 快速开始

### 1. 创建 Agent 团队

```bash
# 创建 Master
./agent.sh start master --port 4097

# 创建各个 Worker Agent
./agent.sh start coder --workdir ~/agents/coder
./agent.sh start reviewer --workdir ~/agents/reviewer
./agent.sh start devops --workdir ~/agents/devops
```

### 2. 查看团队状态

```bash
./agent.sh status
# 输出:
# ● master (port: 4097, HTTP: OK)
# ● coder (port: 5123, HTTP: OK)
# ● reviewer (port: 4789, HTTP: OK)
```

### 3. 发送协作任务

```bash
# 模式一: 流水线 - 开发新功能
./agent.sh send master "创建用户认证系统"
# Master 分解任务并依次发送给:
#   1. coder: "实现 JWT 认证中间件"
#   2. reviewer: "审查认证代码安全性"
#   3. devops: "配置 Redis Session 存储"

# 模式二: 并行 - 数据分析
./agent.sh send master "分析销售数据并生成报告"
# Master 并行发送给:
#   1. analyst: "统计月度销售趋势"
#   2. coder: "编写数据可视化图表"
#   3. analyst: "生成执行摘要"

# 模式三: 讨论 - 技术选型
./agent.sh send master "讨论: 使用 MySQL 还是 PostgreSQL?"
# Master 收集各方意见:
#   1. coder: "从开发便利性分析"
#   2. reviewer: "从性能角度分析"
#   3. devops: "从运维成本分析"
# 然后给出决策
```

## 高级用法

### 自定义 Agent 系统提示词

在 Agent 工作目录创建 `.opencode` 文件:

```bash
# coder Agent 的系统提示
cat > ~/agents/coder/.opencode << 'EOF'
你是一名 Python 后端专家。
- 使用 FastAPI 框架
- 遵循 PEP 8 规范
- 编写单元测试
EOF
```

### Agent 间直接通信

```bash
# coder 完成代码后，通知 reviewer
./agent.sh send reviewer "请审查 coder 刚完成的用户认证模块，重点检查 SQL 注入风险"
```

### 查看执行日志

```bash
# 实时查看所有 Agent 的日志
tmux ls

# 切换到特定 Agent
./agent.sh attach coder

# 在 tmux 内切换窗口 (Ctrl+B 0/1)
```

## 协作流程示例

### 场景: 开发一个完整的 Web 应用

```bash
# Step 1: 创建团队
./agent.sh start master
./agent.sh start frontend --workdir ~/agents/frontend
./agent.sh start backend  --workdir ~/agents/backend
./agent.sh start devops   --workdir ~/agents/devops

# Step 2: Master 分解任务
./agent.sh send master "开发一个 Todo List Web 应用，包含前后端"

# Step 3: 并行开发
# (Master 自动分配)
# backend 收到: "设计 REST API，使用 FastAPI + SQLite"
# frontend 收到: "实现 React 前端界面"

# Step 4: 代码审查
./agent.sh send reviewer "审查 backend 的 API 实现"

# Step 5: 部署
./agent.sh send devops "编写 Docker 部署配置"
```

## 最佳实践

1. **命名规范**: Agent 名称应反映职责，如 `frontend`, `api-designer`
2. **工作目录隔离**: 每个 Agent 有独立工作目录，避免文件冲突
3. **资源限制**: 为每个 Agent 分配合理的 CPU/内存资源
4. **日志管理**: 定期清理 Agent 工作目录中的日志文件
5. **版本控制**: 重要 Agent 的工作目录应纳入 Git 管理

## 故障排查

| 问题 | 原因 | 解决 |
|------|------|------|
| Agent 启动失败 | 端口冲突 | 使用 `--port` 指定其他端口 |
| 指令发送失败 | Agent 未就绪 | 检查 `./agent.sh status` |
| 工作目录混乱 | 多个 Agent 操作同一目录 | 确保每个 Agent 有独立工作目录 |
| 协作结果不一致 | 任务描述不清 | 让 Master 提供更详细的分解 |
