#!/usr/bin/env bash
# @desc 监听萤石摄像头麦克风（从直播流抽 AAC 音频）：播放到本机音响，或录成 wav
# @usage tools/listen_cam.sh [keting|menkou] [秒数=10] [--save <路径>] [--play]
# @rule 说“听听客厅/门口的声音/有没有动静”→ tools/listen_cam.sh keting 10（默认外放）；只想存文件用 --save
# @order 47
set -uo pipefail
SRC="keting"; SECS="10"; SAVE=""; PLAY=1
while [ $# -gt 0 ]; do case "$1" in
  keting|客厅|menkou|门口|usb) SRC="$1"; shift;;
  [0-9]*) SECS="$1"; shift;;
  --save) SAVE="${2:-}"; PLAY=0; shift 2;;
  --play) PLAY=1; shift;;
  *) shift;; esac; done
case "$SRC" in
  keting|客厅) UF=/tmp/myagent_ezviz.url;; menkou|门口) UF=/tmp/myagent_door.url;;
  *) UF=/tmp/myagent_ezviz.url;; esac
URL="$(cat "$UF" 2>/dev/null || true)"
[ -n "$URL" ] || { echo "无地址($UF)；先 tools/ezviz_url.sh 生成" >&2; exit 1; }
OUT="${SAVE:-/tmp/cam_audio_$(date +%H%M%S).wav}"
command -v ffmpeg >/dev/null || { echo "需要 ffmpeg" >&2; exit 3; }
echo "录音 ${SECS}s ← $SRC ..."
if [ "$PLAY" = "1" ] && command -v pw-play >/dev/null; then
  timeout $((SECS+15)) ffmpeg -hide_banner -loglevel error -i "$URL" -t "$SECS" -vn -ac 1 -ar 16000 -f wav - 2>/dev/null | pw-play - 2>/dev/null &
  wait
  echo "（已外放 ${SECS}s）"
else
  timeout $((SECS+15)) ffmpeg -hide_banner -loglevel error -i "$URL" -t "$SECS" -vn -ac 1 -ar 16000 -y "$OUT" 2>/dev/null
  [ -s "$OUT" ] && echo "$OUT"
fi
