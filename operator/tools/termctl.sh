#!/usr/bin/env bash
# tools/termctl.sh — 控制 qterminal 里的命令行任务（opencode 等）
# @desc 控制 qterminal 中的命令行应用：列出标签数 / 截图发微信 / 向指定标签注入指令并回车执行
# @usage tools/termctl.sh tabs | shot [N] [--to 会话] | send <N> "<指令>" [--no-enter]
# @rule 说“命令行/终端有几个任务(标签)”→ 只调 `tools/termctl.sh tabs`，把它输出的 **任务数** 直接回复给用户（不用解释）。
# @rule 说“截图 tabN 的进度/把这个任务进度发我”→ `tools/termctl.sh shot N`；默认发文件传输助手，指定会话用 `shot N --to <会话>`。
# @rule 要控制某个标签里的 opencode/命令行执行一条指令 → `tools/termctl.sh send <N> "<指令>"`（会注入输入框并回车执行）。
set -uo pipefail

# —— 图形会话环境（DISPLAY/XAUTHORITY）——
P="$(pgrep -x pcmanfm-qt | head -1)"
if [ -n "${P:-}" ] && [ -z "${XAUTHORITY:-}" ]; then
    export XAUTHORITY="$(tr '\0' '\n' < /proc/$P/environ 2>/dev/null | sed -n 's/^XAUTHORITY=//p')"
fi
export DISPLAY="${DISPLAY:-:0}"

# —— 可调坐标（相对 qterminal 窗口左上角）——
TAB_X="${TERMCTL_TAB_X:-60}"      # 标签栏最左标签的位置
TAB_Y="${TERMCTL_TAB_Y:-18}"
INPUT_X="${TERMCTL_INPUT_X:-80}"  # opencode 输入框
INPUT_Y="${TERMCTL_INPUT_Y:-778}"

SHOT_BIN="${TERMCTL_SHOT:-/opt/my-agent/agentkit/bin/shot.sh}"
SEND_FILE="${TERMCTL_SEND_FILE:-/opt/my-agent/operator/tools/wechat_send_file.sh}"
MAX_TABS="${TERMCTL_MAX_TABS:-12}"

wid() { wmctrl -lx | awk 'tolower($0)~/qterminal/{print $1; exit}'; }
title() { xdotool getwindowname "$1" 2>/dev/null; }

WID="$(wid)"
if [ -z "${WID:-}" ]; then
    echo "找不到 qterminal 窗口" >&2
    exit 1
fi

_geom() { eval "$(xdotool getwindowgeometry --shell "$WID")"; }
_focus() { xdotool windowactivate --sync "$WID" 2>/dev/null; xdotool windowraise "$WID" 2>/dev/null; sleep 0.3; }

# 切到第 N 个标签（1-based，左起）：先点最左标签，再 Ctrl+PgDn (N-1) 次
goto_tab() {
    local n="$1" i=1
    _focus
    _geom
    xdotool mousemove --sync $((X + TAB_X)) $((Y + TAB_Y)) click 1
    sleep 0.5
    while [ "$i" -lt "$n" ]; do
        xdotool key --clearmodifiers ctrl+Page_Down
        sleep 0.35
        i=$((i + 1))
    done
}

# 列出标签：先输出数量，再逐行 tabN: 标题
cmd_tabs() {
    _focus
    _geom
    xdotool mousemove --sync $((X + TAB_X)) $((Y + TAB_Y)) click 1
    sleep 0.5
    local first t n=0
    first="$(title "$WID")"
    local lines=""
    while :; do
        n=$((n + 1))
        t="$(title "$WID")"
        lines="${lines}tab${n}: ${t}"$'\n'
        xdotool key --clearmodifiers ctrl+Page_Down
        sleep 0.4
        [ "$(title "$WID")" = "$first" ] && break
        [ "$n" -ge "$MAX_TABS" ] && break
    done
    printf '%s' "$n"
    echo
    printf '%s' "$lines"
}

# 截图指定标签并发送微信：shot [N] [--to 会话]
cmd_shot() {
    local n="" to=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --to) to="${2:-}"; shift 2 ;;
            *) n="$1"; shift ;;
        esac
    done
    [ -n "$n" ] && goto_tab "$n"
    _focus
    _geom
    local out="/tmp/termctl_shot_$(date +%s).png"
    "$SHOT_BIN" "$X" "$Y" "$WIDTH" "$HEIGHT" "$out" || { echo "截图失败" >&2; exit 1; }
    if [ -n "$to" ]; then
        "$SEND_FILE" "$out" --to "$to"
    else
        "$SEND_FILE" "$out"
    fi
    echo "$out"
}

# 注入指令并回车：send <N> "<指令>" [--no-enter]
cmd_send() {
    local n="${1:-}"; shift || true
    local text="${1:-}"; shift || true
    local enter=1
    [ "${1:-}" = "--no-enter" ] && enter=0
    if [ -z "$n" ] || [ -z "$text" ]; then
        echo "用法: termctl.sh send <N> \"<指令>\" [--no-enter]" >&2
        exit 2
    fi
    # 单行化，避免多行粘贴确认提示
    text="${text//$'\n'/ }"
    goto_tab "$n"
    _geom
    xdotool mousemove --sync $((X + INPUT_X)) $((Y + INPUT_Y)) click 1
    sleep 0.4
    printf '%s' "$text" | xclip -selection clipboard -l 1 >/dev/null 2>&1
    xdotool key --clearmodifiers ctrl+shift+v
    sleep 0.4
    if [ "$enter" = 1 ]; then
        xdotool key --clearmodifiers Return
        echo "已发送到 tab${n}: ${text}"
    else
        echo "已注入(未回车)到 tab${n}: ${text}"
    fi
}

case "${1:-tabs}" in
    tabs) shift || true; cmd_tabs "$@" ;;
    shot) shift || true; cmd_shot "$@" ;;
    send) shift || true; cmd_send "$@" ;;
    goto) shift || true; goto_tab "${1:-1}"; echo "已切到 tab${1:-1}" ;;
    *) echo "用法: termctl.sh tabs | shot [N] [--to 会话] | send <N> \"<指令>\" [--no-enter]" >&2; exit 2 ;;
esac
