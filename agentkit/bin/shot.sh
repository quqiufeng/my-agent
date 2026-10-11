#!/usr/bin/env bash
# agentkit/bin/shot.sh — 区域截屏（GL 窗口用 root 抓取 + 裁剪）
# 用法: shot.sh <x> <y> <w> <h> <out.png>
set -euo pipefail
x=$1; y=$2; w=$3; h=$4; out=$5
if [ "$w" -le 0 ] || [ "$h" -le 0 ]; then
    echo "shot.sh: bad size ${w}x${h}" >&2
    exit 2
fi
full="${out}.full.png"
import -window root "$full"
convert "$full" -crop "${w}x${h}+${x}+${y}" +repage "$out"
rm -f "$full"
