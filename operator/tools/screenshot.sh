#!/usr/bin/env bash
# tools/screenshot.sh — 截取全屏，返回图片路径
# 用法: screenshot.sh [输出路径]
set -uo pipefail
OUT="${1:-/tmp/friday_shot_$(date +%Y%m%d_%H%M%S).png}"
export DISPLAY="${DISPLAY:-:0}"
if ! import -window root "$OUT" 2>/dev/null; then
    echo "截屏失败（ImageMagick import）" >&2
    exit 1
fi
echo "$OUT"
