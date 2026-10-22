#!/usr/bin/env bash
# tools/living_audio.sh — 在客厅小机箱的 3.5mm 小音响播放音频（本机合成/本地文件 → scp → VLC）
# @desc 客厅小音响播放音频；文本在本机 TTS 合成后 scp 到小机箱，由 VLC 输出到 3.5mm 小音响
# @usage tools/living_audio.sh say <文本> | play <本地文件|http(s) URL> | stop
# @rule 说“客厅/小机箱/小音响 说话/播放音频/放这段声音”→ `say <文本>` 或 `play <文件/URL>`；停止→`stop`。
# @order 49
set -uo pipefail

HOST="${SMALLPC_HOST:-quqiufeng@192.168.1.105}"
REMOTE_PID="/tmp/living-audio.pid"
REMOTE_LOG="/tmp/living-audio.log"
AOUT="${SMALLPC_AOUT:-alsa}"
ADEV="${SMALLPC_ALSA_DEV:-plughw:CARD=PCH,DEV=0}"

usage() {
    echo "用法: tools/living_audio.sh say <文本> | play <本地文件|http(s) URL> | stop" >&2
    exit 2
}

ssh_remote() {
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" "$@"
}

stop_remote() {
    ssh_remote "if [ -f '$REMOTE_PID' ]; then kill \$(cat '$REMOTE_PID') 2>/dev/null || true; rm -f '$REMOTE_PID'; fi" >/dev/null 2>&1 || true
}

play_remote() {
    local src="$1" label="$2"
    stop_remote
    ssh_remote "nohup cvlc --intf dummy --play-and-exit --no-video --aout='$AOUT' --alsa-audio-device='$ADEV' '$src' >'$REMOTE_LOG' 2>&1 </dev/null & echo \$! >'$REMOTE_PID'" >/dev/null 2>&1 || {
        echo "启动小机箱 VLC 失败" >&2
        exit 1
    }
    echo "客厅小音响播放: $label"
}

make_tts() {
    local text="$1" out="$2"
    local nodir
    nodir="$(mktemp -d)"
    printf '#!/bin/sh\nexit 0\n' > "$nodir/pw-play"
    printf '#!/bin/sh\nexit 0\n' > "$nodir/aplay"
    chmod +x "$nodir/pw-play" "$nodir/aplay"
    if ! PATH="$nodir:$PATH" TTS_OUT="$out" /opt/my-agent/voice/say.sh "$text"; then
        rm -rf "$nodir"
        echo "本机 TTS 合成失败" >&2
        exit 1
    fi
    rm -rf "$nodir"
    [ -s "$out" ] || { echo "TTS 未生成音频" >&2; exit 1; }
}

case "${1:-}" in
    say)
        shift
        TEXT="$*"
        [ -n "$TEXT" ] || usage
        WAV="$(mktemp /tmp/living-audio-XXXXXX.wav)"
        trap 'rm -f "$WAV"' EXIT
        make_tts "$TEXT" "$WAV"
        scp -q -o BatchMode=yes "$WAV" "$HOST:/tmp/living-audio-say.wav" || {
            echo "scp 到小机箱失败" >&2
            exit 1
        }
        play_remote "/tmp/living-audio-say.wav" "$TEXT"
        ;;
    play)
        SRC="${2:-}"
        [ -n "$SRC" ] || usage
        case "$SRC" in
            http://*|https://*)
                play_remote "$SRC" "$SRC"
                ;;
            *)
                [ -f "$SRC" ] || { echo "本地文件不存在: $SRC" >&2; exit 1; }
                BASE="$(basename "$SRC")"
                DST="/tmp/living-audio-${BASE//[^A-Za-z0-9._-]/_}"
                scp -q -o BatchMode=yes "$SRC" "$HOST:$DST" || {
                    echo "scp 到小机箱失败" >&2
                    exit 1
                }
                play_remote "$DST" "$BASE"
                ;;
        esac
        ;;
    stop)
        stop_remote
        echo "已停止客厅小音响播放"
        ;;
    *)
        usage
        ;;
esac
