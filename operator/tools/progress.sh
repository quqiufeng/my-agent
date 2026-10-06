#!/usr/bin/env bash
# tools/progress.sh — 查看开发进度：点击 qterminal，逐个 tab 截图 opencode，合并后发微信
# @rule **看开发进度**：说“看看开发进度 / 项目进度 / 各项目怎么样 / 进度”→ `progress.sh`（点击 qterminal，逐个 tab 截图 opencode，合并后发来源会话）。
# @order 13
# 用法: progress.sh [--to 会话]
# 依赖: xdotool（切 tab）、ImageMagick import/montage、wechat_send_file.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"

TO=""
[ "${1:-}" = "--to" ] && TO="${2:-}"
TO="${TO:-${WECHAT_TO:-}}"

QID="$(xdotool search --class qterminal 2>/dev/null | head -1)"
[ -n "$QID" ] || { echo "没找到 qterminal 窗口" >&2; exit 1; }

xdotool windowactivate "$QID" 2>/dev/null; sleep 0.9

TS="$(date +%Y%m%d_%H%M%S)"
TMPD="$(mktemp -d)"
first=""; i=0
while [ "$i" -lt 12 ]; do
    t="$(xdotool getactivewindow getwindowname 2>/dev/null)"
    i=$((i+1))
    if [ -n "$first" ] && [ "$t" = "$first" ]; then break; fi   # 绕回第一个 tab 即停
    [ -z "$first" ] && first="$t"
    f="$TMPD/tab_$(printf '%02d' "$i").png"
    import -window "$QID" "$f" 2>/dev/null
    if [ -s "$f" ]; then echo "tab$i [${t#OC | }]"; else rm -f "$f"; fi
    xdotool key --clearmodifiers ctrl+Next; sleep 0.7
done

mapfile -t PICS < <(ls "$TMPD"/tab_*.png 2>/dev/null | sort)
if [ "${#PICS[@]}" -eq 0 ]; then echo "没截到图（qterminal 无 tab？）" >&2; rm -rf "$TMPD"; exit 1; fi

OUT="/tmp/myagent_progress_${TS}.png"
if [ "${#PICS[@]}" -eq 1 ]; then
    cp "${PICS[0]}" "$OUT"
else
    montage "${PICS[@]}" -tile 1x -geometry +0+8 -background '#202020' "$OUT" 2>/dev/null || cp "${PICS[0]}" "$OUT"
fi
rm -rf "$TMPD"

if [ -n "$TO" ]; then
    "$DIR/wechat_send_file.sh" "$OUT" --to "$TO"
    echo "已发送开发进度（${#PICS[@]} 个 tab）-> $TO"
else
    "$DIR/wechat_send_file.sh" "$OUT"
    echo "已发送开发进度（${#PICS[@]} 个 tab）-> 文件传输助手"
fi
