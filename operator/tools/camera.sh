#!/usr/bin/env bash
# tools/camera.sh — 读摄像头视频流（抓一帧给 Agent 看）
# @desc 读摄像头(USB/RTSP)一帧给 Agent 读图：优先用常驻界面(Flutter)产出的实时帧，其次自抓；也可录像
# @usage tools/camera.sh [--usb N | --rtsp URL] [--out 路径] [--live 秒]
# @rule 要看摄像头画面 → `tools/camera.sh`（返回图片路径，可直接读图）；要一段视频 → `--live <秒>`。
# @order 35
set -uo pipefail
USB="${CAM_USB_INDEX:-0}"; RTSP="${RTSP_URL:-}"; OUT=""; LIVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --usb) USB="${2:-0}"; shift 2 ;;
    --rtsp) RTSP="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --live) LIVE="${2:-5}"; shift 2 ;;
    *) shift ;;
  esac
done
command -v ffmpeg >/dev/null || { echo "需要 ffmpeg" >&2; exit 3; }

if [ -n "$RTSP" ]; then
  LIVE_JPG=/tmp/myagent_cam_rtsp.jpg; SRC=(-rtsp_transport tcp -i "$RTSP")
else
  LIVE_JPG=/tmp/myagent_cam_usb.jpg;  SRC=(-f v4l2 -i "/dev/video$USB")
fi
[ -z "$OUT" ] && OUT="$LIVE_JPG"

# 常驻界面的实时帧（<8s 内更新）—— 直接用它，避免设备被占用
if [ "$LIVE" -eq 0 ] && [ -s "$LIVE_JPG" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$LIVE_JPG" 2>/dev/null || echo 0) ))
  if [ "$age" -le 8 ]; then echo "$LIVE_JPG"; exit 0; fi
fi

if [ "$LIVE" -gt 0 ]; then
  OUT="${OUT%.*}.mp4"
  ffmpeg -loglevel error -y "${SRC[@]}" -t "$LIVE" -c:v libx264 -preset veryfast "$OUT"
else
  ffmpeg -loglevel error -y "${SRC[@]}" -frames:v 1 "$OUT" 2>/tmp/myagent_cam.err
fi
if [ -s "$OUT" ]; then echo "$OUT"; exit 0; fi
# 设备忙 → 回退到实时帧
if [ -s "$LIVE_JPG" ]; then echo "$LIVE_JPG"; exit 0; fi
echo "抓取失败: $(tail -1 /tmp/myagent_cam.err 2>/dev/null)" >&2; exit 1
