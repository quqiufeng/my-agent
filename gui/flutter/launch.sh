#!/usr/bin/env bash
# launch.sh — 桌面图标入口：会话内、单实例启动 my-agent 界面。
# 日志：/tmp/myagent_launch.log
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG=/tmp/myagent_launch.log
{
    echo "=== $(date '+%F %T') ==="
    echo "DISPLAY=$DISPLAY XAUTHORITY=${XAUTHORITY:-}"
    if pgrep -x myagent_ui >/dev/null 2>&1; then
        wmctrl -a "My Agent" 2>/dev/null || true
        echo "already running, bring to front"; exit 0
    fi
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DISPLAY="${DISPLAY:-:0}"
    setsid "$HERE/run.sh" >/dev/null 2>&1 </dev/null &
    echo "started pid $!"
} >> "$LOG" 2>&1
