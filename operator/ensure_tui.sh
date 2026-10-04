#!/usr/bin/env bash
# operator/ensure_tui.sh — 确保大脑 TUI 在线（供转发器在无 TUI 时自动拉起）
# 幂等：已有 attach 直接返回；缺 tmux 会话则起 serve；缺 tui 窗口则建；等 attach 就绪。
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION="${BRAIN_SESSION:-friday-brain}"
PORT="${AGENT_PORT:-4097}"
export DISPLAY="${DISPLAY:-:0}"

# 已有 TUI
if pgrep -f "opencode attach" >/dev/null 2>&1; then
    exit 0
fi

# 缺 tmux 会话 → 起 serve
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux new-session -d -s "$SESSION" -n serve "cd '$DIR' && opencode serve --port $PORT" 2>/dev/null
    for _ in $(seq 1 30); do
        curl -sf "http://localhost:$PORT/global/health" >/dev/null 2>&1 && break
        sleep 1
    done
fi

# 缺 tui 窗口（或 attach 已死留下旧窗口）→ 重建
if tmux list-windows -t "$SESSION" -F "#{window_name}" 2>/dev/null | grep -qx tui; then
    tmux kill-window -t "$SESSION:tui" 2>/dev/null
fi
tmux new-window -d -t "$SESSION" -n tui \
    "cd '$DIR' && opencode attach http://localhost:$PORT; echo; echo '[tui 已退出] 按回车'; read _" 2>/dev/null

# 等 attach 进程就绪，再留一点时间等 TUI 完成初始化
for _ in $(seq 1 15); do
    if pgrep -f "opencode[ ]attach" >/dev/null 2>&1; then
        sleep 4
        exit 0
    fi
    sleep 1
done
echo "[ensure_tui] TUI 启动超时" >&2
exit 1
