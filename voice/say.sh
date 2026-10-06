#!/usr/bin/env bash
# voice/say.sh — 文本转语音 → USB 音响
# 用法: say.sh "要说的文本"
#   TTS: sherpa-onnx + Kokoro（纯 C++）；失败时回退 espeak-ng。
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.sh
. "$DIR/config.sh"

# 英语陪练模式：用英文音色（0-19 为英文女/男声）
if [ -f /tmp/myagent_english_mode ]; then
    export KOKORO_SID="${KOKORO_SID_EN:-3}"
fi

TEXT="${1:-}"
if [ -z "$TEXT" ]; then
    echo "用法: $0 <文本>" >&2
    exit 2
fi

# TTS 播放期间置标志：语音监听据此静音麦克风，避免把自己的播报当输入（回环）
TTS_FLAG="/tmp/myagent_tts_active"
touch "$TTS_FLAG" 2>/dev/null
trap 'rm -f "$TTS_FLAG"' EXIT INT TERM

WAV="${TTS_OUT:-/tmp/voice_tts.wav}"
ok=0

# 1) Kokoro（首选）
if [ -x "$SHERPA_BIN" ] && [ -f "$KOKORO_DIR/model.onnx" ]; then
    if LD_LIBRARY_PATH="${SHERPA_LIB}:${LD_LIBRARY_PATH:-}" "$SHERPA_BIN" \
        --kokoro-model="$KOKORO_DIR/model.onnx" \
        --kokoro-voices="$KOKORO_DIR/voices.bin" \
        --kokoro-tokens="$KOKORO_DIR/tokens.txt" \
        --kokoro-data-dir="$KOKORO_DIR/espeak-ng-data" \
        --kokoro-lexicon="$KOKORO_DIR/lexicon-us-en.txt,$KOKORO_DIR/lexicon-zh.txt" \
        --tts-rule-fsts="$KOKORO_DIR/date-zh.fst,$KOKORO_DIR/number-zh.fst" \
        --num-threads="${TTS_THREADS:-4}" \
        --sid="${KOKORO_SID:-47}" \
        --output-filename="$WAV" "$TEXT" >/dev/null 2>&1; then
        ok=1
    fi
fi

# 2) espeak-ng 兜底
if [ "$ok" != "1" ]; then
    echo "[say] Kokoro 不可用，回退 espeak-ng" >&2
    if ! espeak-ng -v cmn -w "$WAV" "$TEXT" 2>/dev/null; then
        echo "[say] espeak-ng 也失败" >&2
        exit 1
    fi
fi

# 3) 播放：优先 PipeWire（本机默认 sink 即 USB 音响），再 ALSA
play_ok=0
if command -v pw-play >/dev/null 2>&1; then
    if [ -n "${VOICE_SINK:-}" ]; then
        pw-play --target "$VOICE_SINK" "$WAV" 2>/dev/null && play_ok=1
    else
        pw-play "$WAV" 2>/dev/null && play_ok=1
    fi
fi
if [ "$play_ok" != "1" ] && [ -n "${VOICE_SPEAKER:-}" ]; then
    aplay -D "$VOICE_SPEAKER" -q "$WAV" 2>/dev/null && play_ok=1
fi
if [ "$play_ok" != "1" ]; then
    aplay -q "$WAV" 2>/dev/null && play_ok=1
fi
exit 0
