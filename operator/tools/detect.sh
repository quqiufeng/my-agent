#!/usr/bin/env bash
# @desc 对摄像头抓帧做 YOLO 目标识别（**原生 C++/libtorch**，无 Python）：框出人/物并返回带框图路径
# @usage tools/detect.sh [--src usb|keting|menkou|<图片路径>] [--conf 0.35] [--to 会话]
# @rule 说“看看家里有谁 / 门前有人吗 / 识别一下客厅”→ tools/detect.sh [--src keting|menkou]；要发回用 --to
# @order 46
set -uo pipefail
SRC="usb"; CONF="0.35"; TO=""
while [ $# -gt 0 ]; do case "$1" in
  --src) SRC="${2:-usb}"; shift 2;; --conf) CONF="${2:-0.35}"; shift 2;;
  --to) TO="${2:-}"; shift 2;; *) shift;; esac; done
BIN=/opt/my-agent/agentkit/native_yolo/yolo_detect
MODEL=/opt/my-agent/agentkit/native_yolo/yolov8n.torchscript
[ -x "$BIN" ] || bash /opt/my-agent/agentkit/native_yolo/build.sh
case "$SRC" in
  usb) IMG=/tmp/myagent_cam_usb.jpg; NAME=usb;;
  keting|客厅) IMG=/tmp/myagent_cam_stream.jpg; NAME=keting;;
  menkou|门口) IMG=/tmp/myagent_cam_door.jpg; NAME=menkou;;
  *) IMG="$SRC"; NAME="src";;
esac
[ -s "$IMG" ] || { echo "无抓帧: $IMG（相机/app 未在跑？）" >&2; exit 1; }
OUT="/tmp/det_${NAME}.jpg"
"$BIN" "$MODEL" "$IMG" "$OUT" "$CONF"
if [ -n "$TO" ] && [ -s "$OUT" ]; then /opt/my-agent/operator/tools/wechat_send_file.sh "$OUT" --to "$TO" >/dev/null 2>&1 || true; fi
echo "$OUT"
