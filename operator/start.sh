#!/usr/bin/env bash
# operator/start.sh — 启动常驻大脑（tmux + opencode serve + TUI）
# 用法: start.sh [--bg]
#   --bg  只后台启动，不 attach
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION="${BRAIN_SESSION:-my-agent-brain}"
export BRAIN_SESSION="$SESSION"
export DISPLAY="${DISPLAY:-:0}"

# ensure_tui.sh 幂等完成：serve + tui 窗口 + attach 就绪
if ! "$DIR/ensure_tui.sh"; then
    echo "[start] 启动失败（需要 tmux + opencode 且 :4097 可用）" >&2
    exit 1
fi

if [ "${1:-}" = "--bg" ]; then
    echo "已后台启动：tmux attach -t $SESSION"
    exit 0
fi
exec tmux attach -t "$SESSION"
