#!/usr/bin/env bash
# tools/image.sh — 生成图片并发送到微信（默认文件传输助手）
# @desc 生成图片并发送到微信（可指定 小红书/小红薯、朋友圈 尺寸）
# @usage tools/image.sh [小红书|小红薯|朋友圈] "提示词" [--to 会话] [--force]
# @rule **画图/生成图片**：说“画一张…/生成图片…/来个…的图”→ `image.sh "提示词"`。尺寸可**明确指定**：`小红书`/`小红薯`（3:4 竖版 1920×2560）、`朋友圈`（1:1 方图 2048×2048），默认 2560×1440 横版。用法 `image.sh [小红书|小红薯|朋友圈] "提示词"`。出图要几分钟，完成后脚本自动发微信，你只需简短确认。GPU 忙时会被拒绝，稍后再试。
# @order 8
# 用法:
#   tools/image.sh "提示词"                      # 默认 2560x1440 横版
#   tools/image.sh 小红书 "提示词"                # 1920x2560（3:4 竖版）
#   tools/image.sh 小红薯 "提示词"                # 同上（别名）
#   tools/image.sh 朋友圈 "提示词"                # 2048x2048（1:1 方图）
#   tools/image.sh "提示词" 1080 1440            # 自定义宽高
#   tools/image.sh --to 小王 [尺寸] "提示词"      # 发到指定会话（回来源用）
#   tools/image.sh --force "提示词"              # 强制出图（GPU 忙时也跑）
# 说明: 调 static_comfyui 的 backup.sh 出图 → wechat_send_file 发送。
#       预设经 `--preset` 传给 backup.sh（xhs=小红书 1920x2560，pyq=朋友圈 2048x2048）。
#       出图较慢（3080 约 3~5 分钟）。GPU 显存不足默认拒绝，避免 OOM。
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP="${IMAGE_BACKUP:-/opt/static_comfyui/cpp/sd/backup.sh}"

TO=""; PROMPT=""; W=""; H=""; FORCE=0; PRESET=""
args=("$@"); i=0
while [ $i -lt ${#args[@]} ]; do
    a="${args[$i]}"
    case "$a" in
        --to)    TO="${args[$((i+1))]:-}"; i=$((i+2)); continue ;;
        --force) FORCE=1; i=$((i+1)); continue ;;
        小红书|小红薯|xhs|xiaohongshu|竖版) PRESET=xhs; i=$((i+1)); continue ;;
        朋友圈|pyq|moments|方图|方版)       PRESET=pyq; i=$((i+1)); continue ;;
        横版|横图|大屏|默认)                PRESET=""; i=$((i+1)); continue ;;
    esac
    if [[ "$a" =~ ^[0-9]+$ ]]; then
        if [ -z "$W" ]; then W="$a"; else H="$a"; fi
    elif [ -z "$PROMPT" ]; then PROMPT="$a"; fi
    i=$((i+1))
done

# 尺寸：预设优先；否则默认横版 2560x1440（或用户给的宽高）
case "$PRESET" in
    xhs) W=1920; H=2560 ;;
    pyq) W=2048; H=2048 ;;
    *)   W="${W:-2560}"; H="${H:-1440}" ;;
esac

if [ -z "$PROMPT" ]; then
    echo "用法: image.sh [--to 会话] [--force] [小红书|小红薯|朋友圈] \"提示词\" [宽] [高]" >&2
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

SIZE_NAME="横版"; [ "$PRESET" = "xhs" ] && SIZE_NAME="小红书"; [ "$PRESET" = "pyq" ] && SIZE_NAME="朋友圈"
echo "开始出图（$SIZE_NAME ${W}x${H}），请稍候（约 3~5 分钟）..."
if [ -n "$PRESET" ]; then
    "$BACKUP" "$PROMPT" "$OUTBASE" --preset "$PRESET" >"$LOG" 2>&1 || true
else
    "$BACKUP" "$PROMPT" "$OUTBASE" "$W" "$H" >"$LOG" 2>&1 || true
fi

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
