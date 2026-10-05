#!/usr/bin/env bash
# tools/image.sh — 生成图片并发送到微信「文件传输助手」
# 用法:
#   tools/image.sh "提示词"                # 默认 1440x1920（竖版 3:4，适合微信）
#   tools/image.sh "提示词" 1080 1440      # 自定义宽高
# 输出: 保存到 $HOME/gen_<时间戳>.png
# 说明: 调用 static_comfyui 的 backup.sh（img_hires 两阶段 HiRes Fix）出图，
#       再用 wechat_send_file.sh 发到文件传输助手。出图较慢（3080 约 3~5 分钟）。
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP="${IMAGE_BACKUP:-/opt/static_comfyui/cpp/sd/backup.sh}"

PROMPT="${1:-}"
W="${2:-1440}"
H="${3:-1920}"
if [ -z "$PROMPT" ]; then
    echo "用法: image.sh \"提示词\" [宽] [高]" >&2
    exit 2
fi
[ -x "$BACKUP" ] || { echo "backup.sh 不存在: $BACKUP" >&2; exit 1; }

OUTBASE="$HOME/gen_$(date +%Y%m%d_%H%M%S).png"
LOG="/tmp/myagent_img_$(date +%Y%m%d_%H%M%S).log"

echo "开始出图（$W x $H），请稍候..."
"$BACKUP" "$PROMPT" "$OUTBASE" "$W" "$H" >"$LOG" 2>&1 || true

# 解析出图路径（backup.sh 结尾打印 "File:   <path>"，带 ANSI 颜色）
IMG=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -oE 'File:[[:space:]]+/[^[:space:]]+\.png' | tail -1 | sed -E 's/^File:[[:space:]]+//')
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    # 兜底：取日志里最后一个存在的 .png
    for p in $(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -oE '/[^[:space:]]+\.png' | tac); do
        [ -f "$p" ] && { IMG="$p"; break; }
    done
fi
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    echo "出图失败，日志尾部："
    tail -n 20 "$LOG"
    exit 1
fi

echo "出图完成: $IMG"
# 发送到微信文件传输助手（默认）
"$DIR/wechat_send_file.sh" "$IMG"
echo "已发送到微信文件传输助手: $(basename "$IMG")"
