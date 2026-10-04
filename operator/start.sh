#!/usr/bin/env bash
# operator/start.sh — 启动常驻大脑（tmux + opencode）
# 用法: start.sh [--bg]
#   --bg  只后台启动，不 attach
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION="${BRAIN_SESSION:-friday-brain}"
PORT="${AGENT_PORT:-4097}"
export DISPLAY="${DISPLAY:-:0}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "session $SESSION 已存在"
    [ "${1:-}" = "--bg" ] && exit 0
    exec tmux attach -t "$SESSION"
fi

tmux new-session -d -s "$SESSION" -n serve "cd '$DIR' && opencode serve --port $PORT" 2>/dev/null || {
    echo "启动 tmux 失败（需要 tmux + opencode）" >&2; exit 1;
}
echo -n "等待 opencode 就绪 (:$PORT)"
for _ in $(seq 1 30); do
    if curl -sf "http://localhost:$PORT/global/health" >/dev/null 2>&1; then echo " OK"; break; fi
    echo -n "."; sleep 1
done

tmux new-window -t "$SESSION" -n tui "cd '$DIR' && opencode attach http://localhost:$PORT" 2>/dev/null || true
tmux select-window -t "$SESSION:tui" 2>/dev/null || true

if [ "${1:-}" = "--bg" ]; then
    echo "已后台启动：tmux attach -t $SESSION"
    exit 0
fi
exec tmux attach -t "$SESSION"
