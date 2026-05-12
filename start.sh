#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DING_DIR="$SCRIPT_DIR/ding"

case "${1:-}" in
    start)
        # 1. 启动钉钉主进程（接收消息）
        if ! tmux has-session -t bot 2>/dev/null; then
            tmux new-session -d -s bot \
                "cd '$DING_DIR' && python autobot_dingtalk.py"
            echo "钉钉主进程已启动"
        fi
        
        # 2. 启动 Task Worker（执行任务）
        if ! tmux has-session -t worker 2>/dev/null; then
            tmux new-session -d -s worker \
                "cd '$DING_DIR' && python task_worker.py"
            echo "Task Worker 已启动"
        fi
        
        # 3. 启动 Master Agent
        if ! tmux has-session -t master 2>/dev/null; then
            tmux new-session -d -s master -n serve \
                "cd '$SCRIPT_DIR' && opencode serve --port 4097"
            sleep 2
            tmux new-window -t master -n tui \
                "opencode attach http://localhost:4097"
            echo "Master Agent 已启动"
        fi
        
        echo ""
        echo "所有服务已启动:"
        echo "  bot     - 钉钉消息接收"
        echo "  worker  - 任务执行"
        echo "  master  - Agent 管理"
        ;;
        
    stop)
        tmux kill-session -t bot 2>/dev/null && echo "钉钉主进程已停止" || true
        tmux kill-session -t worker 2>/dev/null && echo "Worker 已停止" || true
        tmux kill-session -t master 2>/dev/null && echo "Master 已停止" || true
        ;;
        
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
        
    *)
        echo "用法: $0 start | stop | restart"
        ;;
esac
