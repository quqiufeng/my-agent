#!/usr/bin/env bash
# tools/photo.sh — USB 摄像头拍照并发微信（默认文件传输助手）
# 用法:
#   photo.sh                         # 1920x1080 拍一张发文件传输助手
#   photo.sh --to 小王                # 发给指定会话
#   photo.sh --size 2560x1440        # 指定分辨率（不支持则自动降级 1280x720/640x480）
#   photo.sh --device /dev/video0    # 指定摄像头
#   photo.sh --burst 3               # 连拍 3 张（间隔 1s）全发
#   photo.sh --save /tmp/a.jpg       # 指定保存路径
#   photo.sh --no-send               # 只拍不发，返回路径
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"

DEV="${CAM_DEV:-/dev/video0}"
SIZE="${PHOTO_SIZE:-1920x1080}"
TO=""
OUT=""
NOSEND=0
BURST=1

while [ $# -gt 0 ]; do
    case "$1" in
        --to)     TO="${2:-}";     shift 2 ;;
        --size)   SIZE="${2:-}";   shift 2 ;;
        --device) DEV="${2:-}";    shift 2 ;;
        --save)   OUT="${2:-}";    shift 2 ;;
        --burst)  BURST="${2:-1}"; shift 2 ;;
        --no-send) NOSEND=1;       shift ;;
        *)        shift ;;
    esac
done

[ -e "$DEV" ] || { echo "摄像头不存在: $DEV" >&2; exit 1; }
case "$BURST" in ''|*[!0-9]*) BURST=1 ;; esac
[ "$BURST" -lt 1 ] && BURST=1

OUT="${OUT:-/tmp/myagent_photo_$(date +%Y%m%d_%H%M%S).jpg}"

# 抓一帧（分辨率不支持则降级）
capture() {
    local size="$1" out="$2"
    ffmpeg -hide_banner -loglevel error -f v4l2 -input_format mjpeg \
        -video_size "$size" -i "$DEV" -frames:v 1 -y "$out" 2>/dev/null
    [ -s "$out" ]
}

FILES=()
for i in $(seq 1 "$BURST"); do
    if [ "$BURST" -eq 1 ]; then f="$OUT"; else
        f="/tmp/myagent_photo_$(date +%Y%m%d_%H%M%S)_${i}.jpg"; fi
    ok=0
    for s in "$SIZE" 1280x720 640x480; do
        if capture "$s" "$f"; then ok=1; break; fi
    done
    if [ "$ok" != "1" ]; then
        echo "拍照失败（设备忙或参数不支持）: $DEV" >&2
        [ "${#FILES[@]}" -eq 0 ] && exit 1 || break
    fi
    FILES+=("$f")
    echo "已拍照: $f ($(identify -format '%wx%h' "$f" 2>/dev/null))"
    [ "$i" -lt "$BURST" ] && sleep 1
done

if [ "$NOSEND" = "1" ]; then printf '%s\n' "${FILES[@]}"; exit 0; fi

for f in "${FILES[@]}"; do
    if [ -n "$TO" ]; then
        "$DIR/wechat_send_file.sh" "$f" --to "$TO" >/dev/null 2>&1
    else
        "$DIR/wechat_send_file.sh" "$f" >/dev/null 2>&1
    fi
done
echo "已发送 ${#FILES[@]} 张 -> ${TO:-文件传输助手}"
