#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DING_DIR="$SCRIPT_DIR/ding"

LOG_BOT="/tmp/autobot_bot.log"
LOG_WORKER="/tmp/autobot_worker.log"

start_bot() {
    if pgrep -f "autobot_dingtalk.py" > /dev/null 2>&1; then
        echo "bot 已在运行"
        return
    fi
    nohup python "$DING_DIR/autobot_dingtalk.py" > "$LOG_BOT" 2>&1 &
    echo "bot 已启动 (PID: $!)"
}

start_worker() {
    if pgrep -f "task_worker.py" > /dev/null 2>&1; then
        echo "worker 已在运行"
        return
    fi
    nohup python "$DING_DIR/task_worker.py" > "$LOG_WORKER" 2>&1 &
    echo "worker 已启动 (PID: $!)"
}

start_master() {
    if tmux has-session -t master 2>/dev/null; then
        echo "master 已在运行"
        return
    fi
    tmux new-session -d -s master -n serve \
        "cd '$SCRIPT_DIR' && opencode serve --port 4097"
    sleep 2
    tmux new-window -t master -n tui \
        "opencode attach http://localhost:4097"
    echo "master 已启动"
}

stop_all() {
    pkill -f "autobot_dingtalk.py" 2>/dev/null && echo "bot 已停止" || true
    pkill -f "task_worker.py" 2>/dev/null && echo "worker 已停止" || true
    tmux kill-session -t master 2>/dev/null && echo "master 已停止" || true
}

case "${1:-}" in
    start)
        start_bot
        start_worker
        start_master
        ;;
    stop)
        stop_all
        ;;
    restart)
        stop_all
        sleep 1
        start_bot
        start_worker
        start_master
        ;;
    *)
        echo "用法: $0 start | stop | restart"
        ;;
esac
