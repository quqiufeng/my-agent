#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
    start)
        if ! tmux has-session -t master 2>/dev/null; then
            tmux new-session -d -s master -n serve \
                "cd '$SCRIPT_DIR' && opencode serve --port 4097"
            sleep 2
            tmux new-window -t master -n tui \
                "opencode attach http://localhost:4097"
            echo "Master Agent 已启动"
        fi
        
        if ! tmux has-session -t worker 2>/dev/null; then
            tmux new-session -d -s worker \
                "cd '$SCRIPT_DIR/ding' && python task_worker.py"
            echo "Task Worker 已启动"
        fi
        ;;
        
    stop)
        tmux kill-session -t master 2>/dev/null && echo "Master 已停止" || true
        tmux kill-session -t worker 2>/dev/null && echo "Worker 已停止" || true
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
