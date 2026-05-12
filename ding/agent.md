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
