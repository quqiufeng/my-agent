#!/usr/bin/env bash
# tools/phone_music.sh — 打开手机「汽水音乐」并把声音转到客厅小音响
# @desc 手机汽水音乐播放：确保手机音频转发到小机箱小音响，打开汽水音乐并开始播放
# @usage tools/phone_music.sh play | stop
# @rule 说“打开汽水音乐/手机放汽水音乐/用手机听歌/汽水音乐播放”→ play；停止转发→stop（手机播放/暂停由手机自己控制）。
# @order 51
set -uo pipefail

HOST="${SMALLPC_HOST:-quqiufeng@192.168.1.105}"
PKG="com.luna.music"
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() { echo "用法: tools/phone_music.sh play|stop" >&2; exit 2; }

remote() { ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" "$@"; }

case "${1:-}" in
    play)
        "$TOOL_DIR/phone_audio.sh" start || exit 1
        SERIAL="$(remote "adb devices | awk '\$2==\"device\" {print \$1; exit}'")"
        [ -n "$SERIAL" ] || { echo "未发现 USB 手机设备" >&2; exit 1; }
        if ! remote "adb -s '$SERIAL' shell pm list packages | grep -q '^package:${PKG}\$'"; then
            echo "手机未安装汽水音乐（${PKG}）" >&2
            exit 1
        fi
        remote "adb -s '$SERIAL' shell input keyevent 224 >/dev/null 2>&1 || true; adb -s '$SERIAL' shell wm dismiss-keyguard >/dev/null 2>&1 || true; adb -s '$SERIAL' shell monkey -p '${PKG}' -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 2; adb -s '$SERIAL' shell cmd media_session dispatch play >/dev/null 2>&1 || true; sleep 1; adb -s '$SERIAL' shell dumpsys media_session 2>/dev/null | grep -q 'state=PLAYING' || true"
        echo "已打开汽水音乐，声音走小音响（$SERIAL）"
        ;;
    stop)
        "$TOOL_DIR/phone_audio.sh" stop
        ;;
    *) usage ;;
esac
