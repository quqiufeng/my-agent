#!/usr/bin/env bash
# tools/phone_audio.sh — 手机音频转发到客厅小音响（scrcpy 音频，手动启停）
# @desc 把 USB 连接手机的播放音频经 scrcpy 转发到小机箱 3.5mm 小音响；手机继续自己控制播放/暂停
# @usage tools/phone_audio.sh start | stop | status
# @rule 说“手机声音转到小音响/开手机音频/关手机音频”→ start/stop；只转发音频，不控制手机播放。
# @order 50
set -uo pipefail

HOST="${SMALLPC_HOST:-quqiufeng@192.168.1.105}"
PIDFILE="/tmp/scrcpy-audio.pid"
LOGFILE="/tmp/scrcpy-audio.log"

usage() { echo "用法: tools/phone_audio.sh start|stop|status" >&2; exit 2; }

remote() { ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" "$@"; }

case "${1:-}" in
    start)
        remote 'bash -s' <<'REMOTE'
set -u
if pgrep -f 'scrcpy.*--audio-source=playback' >/dev/null 2>&1; then
    echo "scrcpy 音频已在运行"
    exit 0
fi
SERIAL="$(adb devices | awk '$2=="device" && $1 !~ /:/ {print $1; exit}')"
[ -n "$SERIAL" ] || { echo "未发现 USB 手机设备" >&2; exit 1; }
AUTH="$(ps -eo args | grep '[X]org' | sed -n 's/.*-auth \([^ ]*\).*/\1/p' | head -1)"
[ -n "$AUTH" ] || { echo "找不到 XAUTHORITY" >&2; exit 1; }
export DISPLAY=:0 XAUTHORITY="$AUTH" XDG_RUNTIME_DIR="/run/user/$(id -u)"
nohup scrcpy -s "$SERIAL" --no-window --no-video \
    --audio-source=playback --audio-codec=opus --audio-buffer=200 \
    > /tmp/scrcpy-audio.log 2>&1 </dev/null &
echo $! > /tmp/scrcpy-audio.pid
sleep 3
if kill -0 "$(cat /tmp/scrcpy-audio.pid)" 2>/dev/null; then
    echo "已启动手机音频 → 小音响（$SERIAL）"
else
    echo "启动失败：" >&2
    tail -8 /tmp/scrcpy-audio.log >&2
    exit 1
fi
REMOTE
        ;;
    stop)
        remote 'bash -s' <<'REMOTE'
if [ -f /tmp/scrcpy-audio.pid ]; then
    kill "$(cat /tmp/scrcpy-audio.pid)" 2>/dev/null || true
    rm -f /tmp/scrcpy-audio.pid
fi
pkill -f 'scrcpy.*--audio-source=playback' 2>/dev/null || true
echo "已停止手机音频转发（手机播放不受影响）"
REMOTE
        ;;
    status)
        remote 'bash -s' <<'REMOTE'
if pgrep -f 'scrcpy.*--audio-source=playback' >/dev/null 2>&1; then
    echo "音频转发: 运行中 (PID $(pgrep -f 'scrcpy.*--audio-source=playback' | head -1))"
else
    echo "音频转发: 已停止"
fi
adb devices | awk 'NR==1{next} NF{print "手机: "$1" "$2}'
REMOTE
        ;;
    *) usage ;;
esac
