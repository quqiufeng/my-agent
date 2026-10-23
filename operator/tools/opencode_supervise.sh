#!/usr/bin/env bash
# @desc 监督 opencode 工作：向指定 opencode TUI 标签页发送“继续”并回车，避免任务中断
# @usage tools/opencode_supervise.sh [要发送的文字，默认“继续”]
# @rule 说“监督 opencode/让 opencode 继续/盯着它干活”→ tools/opencode_supervise.sh；默认发送“继续”，可带自定义文字。
# @order 52
# ============================================================
# opencode_retry.sh
#
# 用途:
#   opencode TUI 经常任务没跑完就自己停下来。本脚本用 xdotool
#   模拟人工操作，向指定 opencode 标签页的输入框发送“继续”并
#   回车，让任务接着跑。
#
# 原理（在当前 opencode TUI 内逐步执行，不用 while/后台/cron）:
#   1) 在当前会话执行 sleep 45（等待 45 秒）
#   2) sleep 结束调用 ~/opencode_retry.sh
#   3) 脚本先激活窗口（最小化时自动恢复）-> 切到第 1 个 tab
#      -> 点击底部输入框 -> 用 xclip 粘贴“继续” -> 按回车
#      -> 再把窗口最小化回后台，不干扰其他应用
#   4) 脚本返回后再次 sleep 45，如此往复
#   这样 tab1 每 45 秒收到一次“继续”，任务不会中断，
#   且整个过程不脱离当前 TUI 界面。
#
# 用法:
#   ~/opencode_retry.sh              # 发送“继续”
#   ~/opencode_retry.sh 接着修 bug    # 发送自定义文字
#   sleep 45; ~/opencode_retry.sh   # 手动跑一轮
#
# 可选环境变量:
#   OPENCODE_TAB=first|current      first(默认) 切换到第一个标签页，current 用当前标签页
#   OPENCODE_WINDOW_PATTERN='^OC \|' 窗口标题匹配（默认匹配 opencode 标题）
#   OPENCODE_MINIMIZE=1|0            发完最小化窗口回到后台（默认 1）
#   DRY_RUN=1                       只打印将要执行的操作
#
# 依赖: xdotool、xclip，仅支持 X11。
# ============================================================

set -uo pipefail

MSG="${1:-继续}"
PATTERN="${OPENCODE_WINDOW_PATTERN:-^OC \|}"
TAB_MODE="${OPENCODE_TAB:-first}"
MINIMIZE="${OPENCODE_MINIMIZE:-1}"
DRY_RUN="${DRY_RUN:-0}"

die() { echo "opencode_retry: $*" >&2; exit 1; }

command -v xdotool >/dev/null 2>&1 || die "缺少 xdotool"
command -v xclip   >/dev/null 2>&1 || die "缺少 xclip"
[ -n "${DISPLAY:-}" ] || die "没有 DISPLAY，需在 X11 下运行（Wayland 请用 ydotool）"

run() {
    if [ "$DRY_RUN" = "1" ]; then
        printf '[dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

active="$(xdotool getactivewindow 2>/dev/null || true)"
win=""
if [ -n "$active" ] && xdotool getwindowname "$active" 2>/dev/null | grep -Eq "$PATTERN"; then
    win="$active"
else
    win="$(xdotool search --name "$PATTERN" 2>/dev/null | head -n1)"
fi
[ -n "$win" ] || die "找不到标题匹配 $PATTERN 的窗口"

run xdotool windowactivate --sync "$win"
run sleep 0.3

eval "$(xdotool getwindowgeometry --shell "$win")"

# 点击最左侧标签页（固定坐标，与标题长度无关）
if [ "$TAB_MODE" = "first" ]; then
    run xdotool mousemove --window "$win" 50 39 click 1
    run sleep 0.3
fi

# 点击左侧输入框（底部，避开状态栏）
run xdotool mousemove --window "$win" $((WIDTH / 5)) $((HEIGHT - 120)) click 1
run sleep 0.2

# 剪贴板粘贴，避免 xdotool type 输入中文失败；粘贴后恢复原剪贴板
old_clip="$(xclip -o -selection clipboard 2>/dev/null || true)"
if [ "$DRY_RUN" = "1" ]; then
    printf '[dry-run] 粘贴并回车: %s\n' "$MSG"
    [ "$MINIMIZE" = "1" ] && printf '[dry-run] 最小化窗口 %s\n' "$win"
else
    printf '%s' "$MSG" | setsid xclip -selection clipboard >/dev/null 2>&1
    sleep 0.1
    xdotool key ctrl+shift+v
    sleep 0.2
    [ -z "$old_clip" ] || printf '%s' "$old_clip" | setsid xclip -selection clipboard >/dev/null 2>&1
    xdotool key Return
    if [ "$MINIMIZE" = "1" ]; then
        sleep 0.5
        xdotool windowminimize "$win"
    fi
fi

echo "已向窗口 $win 发送: $MSG"
