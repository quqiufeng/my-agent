#!/usr/bin/env bash
# 文本 → 主机 TTS(WAV) → scp → Kindle 扬声器 aplay 播报
# 用法: say_on_kindle.sh "文本"
#       kui page | say_on_kindle.sh          # 朗读当前页
set -uo pipefail
. /opt/my-agent/voice/config.sh
K=${KINDLE_HOST:-kindle}
W=${TTS_WAV:-/tmp/kindle_tts.wav}

if [ $# -gt 0 ]; then TEXT="$*"; else TEXT="$(cat)"; fi
TEXT="$(printf '%s' "$TEXT" | tr '\n' ' ')"
if [ -z "${TEXT// /}" ]; then echo "无文本" >&2; exit 2; fi

ok=0
if [ -x "$SHERPA_BIN" ] && [ -f "$KOKORO_DIR/model.onnx" ]; then
    LD_LIBRARY_PATH="$SHERPA_LIB:${LD_LIBRARY_PATH:-}" "$SHERPA_BIN" \
        --kokoro-model="$KOKORO_DIR/model.onnx" \
        --kokoro-voices="$KOKORO_DIR/voices.bin" \
        --kokoro-tokens="$KOKORO_DIR/tokens.txt" \
        --kokoro-data-dir="$KOKORO_DIR/espeak-ng-data" \
        --kokoro-lexicon="$KOKORO_DIR/lexicon-us-en.txt,$KOKORO_DIR/lexicon-zh.txt" \
        --tts-rule-fsts="$KOKORO_DIR/date-zh.fst,$KOKORO_DIR/number-zh.fst" \
        --num-threads="${TTS_THREADS:-4}" --sid="${KOKORO_SID:-47}" \
        --output-filename="$W" "$TEXT" >/dev/null 2>&1 && ok=1
fi
if [ "$ok" != 1 ]; then
    echo "[tts] Kokoro 不可用，回退 espeak-ng" >&2
    espeak-ng -v cmn -w "$W" "$TEXT" || exit 1
fi

scp -O -q "$W" "$K:/mnt/us/ui/tts.wav" || { echo "scp 失败" >&2; exit 1; }
ssh -o BatchMode=yes "$K" 'amixer -c 0 sset "Master Output Playback Volume" 15 >/dev/null 2>&1; aplay /mnt/us/ui/tts.wav'
