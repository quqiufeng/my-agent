#!/usr/bin/env bash
# voice/cosyvoice.sh — 克隆音色管理 + 用指定音色发声（CosyVoice3，纯 C++/LuaJIT）
# 用法:
#   cosyvoice.sh list                       # 列出已注册音色
#   cosyvoice.sh add <名> <参考.wav> ["参考文本"]   # 注册音色（留空文本则用 SenseVoice 自动转写）
#   cosyvoice.sh synth <名> "文本" <out.wav> [语速] # 合成到文件
#   cosyvoice.sh speak <名> "文本" [语速]          # 合成并播放到音响
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/config.sh"

cmd="${1:-}"; shift || true
mkdir -p "$VOICES_DIR" 2>/dev/null

play() { # $1=wav
    local w="$1" ok=0
    if command -v pw-play >/dev/null 2>&1; then
        if [ -n "${VOICE_SINK:-}" ]; then pw-play --target "$VOICE_SINK" "$w" 2>/dev/null && ok=1
        else pw-play "$w" 2>/dev/null && ok=1; fi
    fi
    if [ "$ok" != "1" ] && [ -n "${VOICE_SPEAKER:-}" ]; then aplay -D "$VOICE_SPEAKER" -q "$w" 2>/dev/null && ok=1; fi
    if [ "$ok" != "1" ]; then aplay -q "$w" 2>/dev/null && ok=1; fi
    return 0
}

synth() { # $1=name $2=text $3=out $4=speed
    local name="$1" text="$2" out="$3" speed="${4:-1.0}"
    local gguf="$VOICES_DIR/$name.gguf"
    [ -f "$gguf" ] || { echo "音色不存在: $name（用 cosyvoice.sh add 注册）" >&2; return 1; }
    LD_LIBRARY_PATH="$COSYVOICE_LIB_DIR:$COSYVOICE_BIN_DIR:${LD_LIBRARY_PATH:-}" \
        luajit "$DIR/cosyvoice_tts.lua" "$gguf" "$out" "$text" "$speed"
}

transcribe() { # $1=wav -> 文本（SenseVoice，转标准 16k 单声道 + CPU 避免 CUDA 崩溃）
    local w="$1" tmp="/tmp/cv_asr_$$.wav" out
    ffmpeg -y -i "$w" -ar 16000 -ac 1 -c:a pcm_s16le "$tmp" >/dev/null 2>&1 || tmp="$w"
    out="$("$SENSEVOICE_BIN" -m "$SENSEVOICE_MODEL" -ng -t "${SENSEVOICE_THREADS:-4}" -l "${SENSEVOICE_LANG:-zh}" "$tmp" 2>/dev/null \
        | sed -E 's/<\|[^|]*\|>//g; s/\[[0-9.]+-[0-9.]+\]//g' | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ +//; s/ +$//')"
    [ "$tmp" != "$w" ] && rm -f "$tmp"
    case "$out" in *gdb*|*LWP*|*Inferior*|*subchunk*) return 1 ;; esac
    printf '%s' "$out"
}

case "$cmd" in
    list)
        shopt -s nullglob
        found=0
        for f in "$VOICES_DIR"/*.gguf; do
            n="$(basename "$f" .gguf)"; found=1
            txt=""; [ -f "$VOICES_DIR/$n.txt" ] && txt="$(cat "$VOICES_DIR/$n.txt")"
            printf '%-20s %s\n' "$n" "$txt"
        done
        [ "$found" = 0 ] && echo "(无音色；用 cosyvoice.sh add <名> <参考.wav> 注册)"
        ;;
    add)
        name="${1:-}"; ref="${2:-}"; txt="${3:-}"
        [ -n "$name" ] && [ -f "$ref" ] || { echo "用法: cosyvoice.sh add <名> <参考.wav> [参考文本]" >&2; exit 2; }
        if [ -z "$txt" ]; then
            echo "未给参考文本，用 SenseVoice 自动转写(CPU)..."
            if ! txt="$(transcribe "$ref")" || [ -z "$txt" ]; then
                echo "转写失败，请手动提供参考文本：cosyvoice.sh add $name <ref.wav> \"文本\"" >&2; exit 1
            fi
            echo "  文本: $txt"
        fi
        gguf="$VOICES_DIR/$name.gguf"
        if ! "$COSYVOICE_CLI" --frontend-only \
            --speech-tokenizer "$COSYVOICE_TOKENIZER" \
            --campplus "$COSYVOICE_CAMPPLUS" \
            --prompt-audio "$ref" \
            --prompt-text "$txt" \
            --prompt-speech-output "$gguf" >/tmp/cosyvoice_add.log 2>&1; then
            echo "注册失败，日志："; tail -15 /tmp/cosyvoice_add.log; exit 1
        fi
        cp -f "$ref" "$VOICES_DIR/$name.wav" 2>/dev/null
        printf '%s' "$txt" > "$VOICES_DIR/$name.txt"
        echo "已注册音色: $name  (文本: $txt)"
        ;;
    synth)
        name="${1:-}"; text="${2:-}"; out="${3:-/tmp/cosyvoice_out.wav}"; speed="${4:-1.0}"
        [ -n "$name" ] && [ -n "$text" ] || { echo "用法: cosyvoice.sh synth <名> \"文本\" <out.wav> [语速]" >&2; exit 2; }
        synth "$name" "$text" "$out" "$speed" || exit 1
        echo "$out"
        ;;
    del)
        name="${1:-}"; [ -n "$name" ] || { echo "用法: cosyvoice.sh del <名>" >&2; exit 2; }
        rm -f "$VOICES_DIR/$name.gguf" "$VOICES_DIR/$name.wav" "$VOICES_DIR/$name.txt"
        echo "已删除音色: $name"
        ;;
    say|speak)
        name="${1:-}"; text="${2:-}"; speed="${3:-1.0}"
        [ -n "$name" ] && [ -n "$text" ] || { echo "用法: cosyvoice.sh speak <名> \"文本\" [语速]" >&2; exit 2; }
        out="${TTS_OUT:-/tmp/voice_tts.wav}"
        synth "$name" "$text" "$out" "$speed" || exit 1
        play "$out"
        ;;
    *)
        echo "用法: cosyvoice.sh {list | add <名> <参考.wav> [文本] | synth <名> \"文本\" <out.wav> | speak <名> \"文本\"}" >&2
        exit 2 ;;
esac
