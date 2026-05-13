## OpenCode 集成：tmux + HTTP API

通过 tmux 运行 OpenCode Server，支持 HTTP API 发送指令和 TUI 界面查看执行过程。

### 启动方式

```bash
# 创建 tmux session，启动 serve 模式（HTTP API）
tmux new-session -d -s opencode-dev -n serve "opencode serve --port 4097"

# 等待服务启动后，创建第二个窗口 attach 到 server
tmux new-window -t opencode-dev -n tui "opencode attach http://localhost:4097"
```

### 使用方法

```bash
# attach 查看 TUI 界面（默认显示 tui 窗口）
tmux attach -t opencode-dev

# 在 tmux 内切换窗口
Ctrl+B 然后按 0  # 切换到 serve 窗口（查看 server 日志）
Ctrl+B 然后按 1  # 切换到 tui 窗口（查看 AI 执行界面）

# 退出 tmux（保留后台运行）
Ctrl+B 然后按 D
```

### HTTP 发送指令

```bash
# 发送提示词
curl -X POST http://localhost:4097/tui/append-prompt \
  -H "Content-Type: application/json" \
  -d '{"text": "查看当前目录结构"}'

# 提交执行
curl -X POST http://localhost:4097/tui/submit-prompt

# 检查服务健康状态
curl http://localhost:4097/global/health
```

### 功能特点

- **双重控制**：既可以通过 HTTP API 发送指令，也可以 attach 到 tmux 查看实时执行过程
- **后台运行**：detach 后 server 和 tui 都在后台继续运行
- **多窗口管理**：serve 窗口显示 API 服务日志，tui 窗口显示 OpenCode 交互界面
- **安全提示**：生产环境建议设置 `OPENCODE_SERVER_PASSWORD` 启用 HTTP Basic Auth

---

## #agent 指令执行完整路径

用户在钉钉发送 `#agent coder 写一个 Python 爬虫`，系统处理流程如下：

### 1. 钉钉网关接收（主进程）

```
ding/autobot_dingtalk.py:105  process()
  ↓
ding/autobot_dingtalk.py:182  正则匹配 #(\w+) → directive_name="agent"
  ↓
ding/autobot_dingtalk.py:187  回复 "执行指令..."（让用户知道已收到）
  ↓
ding/autobot_dingtalk.py:189  dispatch_task("agent", {"raw": text}, session_webhook)
  ↓
ding/autobot_dingtalk.py:60   序列化任务 → /tmp/autobot_tasks/task.json
```

**关键代码** (`autobot_dingtalk.py:182-189`):
```python
directive_match = re.match(r'#(\w+)', text)
if directive_match:
    directive_name = directive_match.group(1)  # "agent"
    result = self.dispatch_task(directive_name, {"raw": text}, session_webhook=session_webhook)
```

### 2. 任务调度（Worker 进程）

```
ding/task_worker.py:86    run_worker() 轮询检测到 task.json
  ↓
ding/task_worker.py:99    do_task(task)
  ↓
ding/task_worker.py:45    get_task("agent")
  ↓
ding/tasks/registry.py:91 get_task() → 注册表查找 "agent" 类型
  ↓
ding/tasks/registry.py:42 get_instance() → 实例化 AgentTask
  ↓
ding/tasks/agent.py:30    execute(content, session_webhook)
```

**关键代码** (`task_worker.py:43-56`):
```python
task_handler = get_task(task_type)  # 从注册表获取 AgentTask 实例
task_result = task_handler.execute(content, session_webhook)
result.update(task_result)
```

### 3. Agent 任务执行（核心逻辑）

```
ding/tasks/agent.py:30   execute()
  ↓
ding/tasks/agent.py:42   _parse_args(args_str) → ("coder", "写一个 Python 爬虫")
  ↓
ding/tasks/agent.py:47   _get_agent_port("coder") → 4098
  ↓
ding/tasks/agent.py:51   _is_agent_running("coder") → tmux has-session 检查
```

#### 分支 A：Agent 未运行（自动启动）

```
  ├─ 未运行
  │   ↓
  │   ding/tasks/agent.py:101 _start_agent("coder", 4098)
  │     ├─ 创建 ~/agents/coder/ 工作目录
  │     └─ tmux new-session -d -s coder "cd ~/agents/coder && opencode serve --port 4098"
  │   ↓
  │   ding/tasks/agent.py:128 _wait_for_agent(4098, timeout=10)
  │     └─ 轮询 GET http://localhost:4098/global/health
  │   ↓
  │   就绪后继续
```

#### 分支 B：Agent 已运行（直接发送）

```
  └─ 已运行
      ↓
      直接进入下一步
```

### 4. 发送指令到 OpenCode Server

```
ding/tasks/agent.py:142   _send_instruction("coder", "http://localhost:4098", "写一个 Python 爬虫")
  ↓
POST http://localhost:4098/tui/append-prompt
  Body: {"text": "写一个 Python 爬虫"}
  ↓
POST http://localhost:4098/tui/submit-prompt
  ↓
写入 /tmp/autobot_tasks/result.json
```

### 5. 结果返回（主进程）

```
ding/autobot_dingtalk.py:65   主进程读取 result.json
  ↓
ding/autobot_dingtalk.py:193  检查 exec_responses 标记
  ├─ 包含 __MARKDOWN_SENT__ → 不发送文本（已用 Markdown 格式发送）
  └─ 普通结果 → autobot_dingtalk.py:200 reply_text() 回复用户
```

**关键代码** (`autobot_dingtalk.py:193-196`):
```python
exec_responses = result.get('exec_responses', '')
if exec_responses and ('__MEDIA_ID__' in exec_responses or '__MARKDOWN_SENT__' in exec_responses):
    return AckMessage.STATUS_OK, 'OK'  # Worker 已发送，主进程不再重复
```

### 6. Markdown 消息发送（Worker 内）

```
ding/tasks/agent.py:161  构建 Markdown 内容
  ↓
ding/tasks/agent.py:167  dt.send_markdown(session_webhook, "Agent 指令", markdown_content)
  ↓
exec_responses = "__MARKDOWN_SENT__"
```

**回复格式示例**:
```markdown
### Agent 指令已发送

**目标 Agent:** `coder`
**服务地址:** `http://localhost:4098`
**指令内容:**
```
写一个 Python 爬虫
```

**查看执行:** `tmux attach -t coder`
```

---

## 架构总结

| 进程 | 文件 | 职责 |
|------|------|------|
| **主进程** | `autobot_dingtalk.py` | 接收钉钉消息、通过文件系统与 Worker 通信、回复用户 |
| **Worker** | `task_worker.py` | 轮询任务文件、调用注册表分发执行 |
| **注册表** | `tasks/registry.py` | 动态扫描加载 `tasks/*.py` 插件 |
| **任务** | `tasks/agent.py` | 解析指令、启动/管理 Agent、发送指令到 OpenCode |
| **Agent** | `opencode serve` | 实际执行 AI 任务（运行在 tmux session 中） |

**通信方式**：
- 主进程 ↔ Worker：文件系统（`/tmp/autobot_tasks/`）
- Worker ↔ Agent：HTTP REST API（`localhost:4097+`）
- Worker ↔ 钉钉：Webhook 直接发送 Markdown 消息
- 用户 ↔ Agent：tmux attach 查看 TUI 实时执行
