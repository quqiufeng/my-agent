#!/usr/bin/env bash
# tools/image.sh — 生成图片并发送到微信（默认文件传输助手）
# @rule **画图/生成图片**：说“画一张…/生成图片…/来个…的图”→ `image.sh "提示词"`（默认 1440x1920 竖版）。出图要几分钟，完成后脚本自动把图发到微信，你只需简短确认。GPU 忙时会被拒绝，稍后再试。
# @order 8
# 用法:
#   tools/image.sh "提示词"                     # 默认 1440x1920（竖版 3:4）
#   tools/image.sh "提示词" 1080 1440           # 自定义宽高
#   tools/image.sh --to 小王 "提示词"            # 发到指定会话（回来源用）
#   tools/image.sh --force "提示词"              # 强制出图（GPU 忙时也跑）
# 说明: 调 static_comfyui 的 sd.cpp img_hires 两阶段 HiRes Fix 出图 → wechat_send_file 发送。
#       出图较慢（3080 约 3~5 分钟）。GPU 显存不足默认拒绝，避免 OOM。
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP="${IMAGE_BACKUP:-/opt/static_comfyui/cpp/sd/backup.sh}"

TO=""; PROMPT=""; W=""; H=""; FORCE=0
args=("$@"); i=0
while [ $i -lt ${#args[@]} ]; do
    a="${args[$i]}"
    if [ "$a" = "--to" ]; then TO="${args[$((i+1))]:-}"; i=$((i+2)); continue; fi
    if [ "$a" = "--force" ]; then FORCE=1; i=$((i+1)); continue; fi
    if [[ "$a" =~ ^[0-9]+$ ]]; then
        if [ -z "$W" ]; then W="$a"; else H="$a"; fi
    elif [ -z "$PROMPT" ]; then PROMPT="$a"; fi
    i=$((i+1))
done
W="${W:-1440}"; H="${H:-1920}"

if [ -z "$PROMPT" ]; then
    echo "用法: image.sh [--to 会话] [--force] \"提示词\" [宽] [高]" >&2
    exit 2
fi
[ -x "$BACKUP" ] || { echo "backup.sh 不存在: $BACKUP" >&2; exit 1; }

# GPU 显存检查（避免和别的任务抢显存 OOM）
if command -v nvidia-smi >/dev/null 2>&1; then
    FREE="$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')"
    if [ -n "${FREE:-}" ] && [ "$FREE" -lt 8000 ] && [ "$FORCE" != "1" ]; then
        echo "GPU 显存不足（空闲 ${FREE} MiB），出图可能 OOM/极慢。稍后再试或加 --force。" >&2
        exit 3
    fi
fi

OUTBASE="$HOME/gen_$(date +%Y%m%d_%H%M%S).png"
LOG="/tmp/myagent_img_$(date +%Y%m%d_%H%M%S).log"

echo "开始出图（$W x $H），请稍候（约 3~5 分钟）..."
"$BACKUP" "$PROMPT" "$OUTBASE" "$W" "$H" >"$LOG" 2>&1 || true

# 解析出图路径（backup.sh 结尾打印 "File:   <path>"，带 ANSI 颜色）
IMG=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -oE 'File:[[:space:]]+/[^[:space:]]+\.png' | tail -1 | sed -E 's/^File:[[:space:]]+//')
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    for p in $(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -oE '/[^[:space:]]+\.png' | tac); do
        [ -f "$p" ] && { IMG="$p"; break; }
    done
fi
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    echo "出图失败，日志尾部："; tail -n 20 "$LOG"; exit 1
fi

echo "出图完成: $IMG"
if [ -n "$TO" ]; then
    "$DIR/wechat_send_file.sh" "$IMG" --to "$TO"
    echo "已发送到微信「$TO」: $(basename "$IMG")"
else
    "$DIR/wechat_send_file.sh" "$IMG"
    echo "已发送到微信文件传输助手: $(basename "$IMG")"
fi
