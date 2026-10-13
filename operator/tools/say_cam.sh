#!/usr/bin/env bash
# @desc 让萤石摄像头喇叭播放一段音频（对讲/喊话/播报）：上传音频到萤石 → 设备播放
# @usage tools/say_cam.sh [keting|menkou] <音频.wav>
# @rule 说“对客厅喊话 / 让门口响一下 / 往客厅播报”→ tools/say_cam.sh keting <wav>（**需已开通萤石「语音提醒」资源包**，否则返回 111000）
# @order 48
set -uo pipefail
ENVF="${EZVIZ_ENV:-$HOME/.env}"; [ -f "$ENVF" ] && set -a && . "$ENVF" && set +a
API=https://open.ys7.com
SRC="keting"; WAV=""
for a in "$@"; do case "$a" in
  keting|客厅) SRC=802657358;; menkou|门口) SRC=815311181;;
  *.wav|*.mp3|*.aac) WAV="$a";; [0-9]*) SRC="$a";; esac; done
[ -n "$WAV" ] || { echo "用法: say_cam.sh [keting|menkou|<序列号>] <音频.wav>" >&2; exit 2; }
[ -s "$WAV" ] || { echo "无音频: $WAV" >&2; exit 2; }
TOK=$(curl -s -X POST "$API/api/lapp/token/get" -d "appKey=$EZVIZ_APPKEY" -d "appSecret=$EZVIZ_APPSECRET" | jq -r '.data.accessToken // empty')
[ -n "$TOK" ] || { echo "取 token 失败" >&2; exit 1; }
URL=$(curl -s -X POST "$API/api/lapp/voice/upload" -F "accessToken=$TOK" -F "voiceFile=@$WAV" | jq -r '.data.url // empty')
[ -n "$URL" ] || { echo "上传失败" >&2; exit 1; }
RESP=$(curl -s -X POST "$API/api/lapp/voice/send" --data-urlencode "accessToken=$TOK" \
  -d "deviceSerial=$SRC" -d "channelNo=1" --data-urlencode "fileUrl=$URL")
echo "$RESP" | jq -r 'if .code=="200" then "已让设备播放" else "失败: "+.code+" "+.msg end'
