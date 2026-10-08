#!/usr/bin/env bash
# tools/video_dub.sh — 给「拍好的视频」配音+字幕（音色可克隆；字幕文案可短不可超视频时长）
# 字幕样式：Noto Sans CJK SC Bold，橙色正常字+黑边，去标点、每行12字、每条最多两行（超长自动拆条）。
# 【推荐流程 · 保证视频正确性】
#   1) 先 `video_dub.sh <视频> "<文案>" --probe` → 只生成配音并打印「视频 Xs ｜ 配音 Ys ｜ 段数」
#   2) 比对：配音 Ys 必须 ≤ 视频 Xs（可短不可超）；超了 → 精简文案或调 `--speed`，反复 probe 直到放得下
#   3) 放得下再正式合成：`video_dub.sh <视频> "<文案>" --fg --out out.mp4`
#   每个配音段=一条字幕（≤24字/两行），声画一一对应，不会错位。
# @desc 给已有视频配音+字幕（可克隆音色）；先用 --probe 生成配音比对时长，确保不超视频，再合成
# @usage tools/video_dub.sh <视频> "文案1|文案2|…" [--probe] [--speed 0.85] [--fit] [--ref 参考.wav] [--voice 名] [--out out.mp4] [--to 会话] [--send] [--keep-audio] [--fg]
# @rule **给视频配音+字幕**：说“给这个视频配音+字幕 / 给视频配字幕 / 加旁白” → 拿到视频和文案资料后，按**视频时长**把资料重构为分镜字幕（每段≤24字、可短不可超、每次措辞不同）。**务必先跑 `--probe` 只生成配音比对时长**（`工具会打印「视频 Xs ｜ 配音 Ys」`），确认 配音时长 ≤ 视频时长 再正式合成；超了就精简文案或调 `--speed`（默认0.85慢速）重测，直到放得下——这样保证成片正确。给了参考音频就 `--ref <wav>` 克隆音色，默认音色则不加；`--voice <名>` 用已注册音色。默认不发微信（加 `--send` 才发）。
# @order 15
set -uo pipefail
ORIG_ARGS=("$@")
DIR="$(cd "$(dirname "$0")" && pwd)"
. /opt/my-agent/voice/config.sh
FONT_STYLE="Default,Noto Sans CJK SC Bold,14,&H0000D2FF,&H0000D2FF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,3,0,2,10,10,24,1"
BLUR=""
PAUSE=0.3; INTRO=0.3

VIDEO=""; TEXT=""; REF=""; VOICE="${SAY_VOICE:-}"; OUT=""; TO=""; NOSEND=1; KEEPAUDIO=0; FG=0; SPEED="${VDUB_SPEED:-0.85}"; PROBE=0; FIT=0; CLONE_SPEED="${VDUB_CLONE_SPEED:-1.0}"
while [ $# -gt 0 ]; do
    case "$1" in
        --ref)   REF="${2:-}"; shift 2 ;;
        --voice) VOICE="${2:-}"; shift 2 ;;
        --speed) SPEED="${2:-0.85}"; shift 2 ;;
        --clone-speed) CLONE_SPEED="${2:-1.0}"; shift 2 ;;
        --probe) PROBE=1; shift ;;
        --fit)   FIT=1; shift ;;
        --out)   OUT="${2:-}"; shift 2 ;;
        --to)    TO="${2:-}"; NOSEND=0; shift 2 ;;
        --send)  NOSEND=0; shift ;;
        --no-send) NOSEND=1; shift ;;
        --keep-audio) KEEPAUDIO=1; shift ;;
        --fg)    FG=1; shift ;;
        *)  if [ -z "$VIDEO" ]; then VIDEO="$1"; elif [ -z "$TEXT" ]; then TEXT="$1"; fi; shift ;;
    esac
done
[ -n "$VIDEO" ] && [ -f "$VIDEO" ] || { echo "用法: video_dub.sh <视频> \"文案1|文案2|…\" [--ref 参考.wav] [--voice 名] [--out out.mp4]" >&2; exit 2; }
[ -n "$TEXT" ] || { echo "缺文案（用 | 分隔每段）" >&2; exit 2; }
# 文案可来自文件
if [ -f "$TEXT" ]; then TEXT="$(tr '\n' '|' < "$TEXT" | sed 's/|$//')"; fi
[ -n "$OUT" ] || OUT="${VIDEO%.*}_dubbed.mp4"

wrap_text() { # $1=文本 $2=每行汉字数（默认12）；去标点后硬折行
    local t="$1" n="${2:-12}" out="" i
    t="$(printf '%s' "$t" | sed -E "s/[，。！？、；：·,.!?;:…—－（）()【】「」『』《》〈〉“”‘’\"' 　]//g")"
    local len="${#t}"
    for ((i = 0; i < len; i += n)); do
        local c="${t:i:n}"
        out="${out:+$out\\N}$c"
    done
    printf '%s' "$out"
}

clean_punct() { printf '%s' "$1" | sed -E "s/[，。！？、；：·,.!?;:…—－（）()【】「」『』《》〈〉“”‘’\"' 　]//g"; }
# 输出字幕：每条最多 2 行(24字)，超长拆成多条（按时间均分）
emit_subs() { # $1=start $2=dur $3=text
    local clean n i dt part st en
    clean="$(clean_punct "$3")"
    local len="${#clean}"
    n=$(( (len + 23) / 24 )); [ "$n" -lt 1 ] && n=1
    dt="$(awk "BEGIN{print $2/$n}")"
    for ((i = 0; i < n; i++)); do
        part="${clean:i*24:24}"
        [ -z "$part" ] && continue
        st="$(awk "BEGIN{printf \"0:%02d:%05.2f\", int(($1+$i*$dt)/60), ($1+$i*$dt)%60}")"
        en="$(awk "BEGIN{printf \"0:%02d:%05.2f\", int(($1+($i+1)*$dt)/60), ($1+($i+1)*$dt)%60}")"
        printf 'Dialogue: 0,%s,%s,Default,,0,0,0,,%s%s\n' "$st" "$en" "$BLUR" "$(wrap_text "$part" 12)" >> "$ASS"
    done
}

# 逐段配音（含语速调节）；使用 run_dub 的局部变量（bash 动态作用域）
tts_all() {
    local i wav tx used_clone
    for i in $(seq 0 $((${#SEG[@]} - 1))); do
        wav="$WORK/aud/$((i+1)).wav"; tx="${SEG[$i]}"; rm -f "$wav"; used_clone=0
        [ -z "$tx" ] && continue
        if [ -n "$USE_VOICE" ] && [ -f "$VOICES_DIR/$USE_VOICE.gguf" ]; then
            "$DIR/../../voice/cosyvoice.sh" synth "$USE_VOICE" "$tx" "$wav" "$CLONE_SPEED" >>"$LOG" 2>&1 && [ -s "$wav" ] && used_clone=1
        fi
        if [ ! -s "$wav" ]; then
            LD_LIBRARY_PATH="${SHERPA_LIB}:${LD_LIBRARY_PATH:-}" "$SHERPA_BIN" \
                --kokoro-model="$KOKORO_DIR/model.onnx" --kokoro-voices="$KOKORO_DIR/voices.bin" \
                --kokoro-tokens="$KOKORO_DIR/tokens.txt" --kokoro-data-dir="$KOKORO_DIR/espeak-ng-data" \
                --kokoro-lexicon="$KOKORO_DIR/lexicon-us-en.txt,$KOKORO_DIR/lexicon-zh.txt" \
                --tts-rule-fsts="$KOKORO_DIR/date-zh.fst,$KOKORO_DIR/number-zh.fst" \
                --num-threads="${TTS_THREADS:-4}" --sid="${KOKORO_SID:-47}" \
                --output-filename="$wav" "$tx" >>"$LOG" 2>&1 || true
            # Kokoro 才套 atempo（克隆已用原生语速）
            if [ "$used_clone" != "1" ] && [ "$SPEED" != "1" ] && [ "$SPEED" != "1.0" ] && [ -s "$wav" ]; then
                if ffmpeg -y -i "$wav" -filter:a "atempo=$SPEED" "$WORK/aud/sp_$i.wav" >>"$LOG" 2>&1; then
                    mv -f "$WORK/aud/sp_$i.wav" "$wav"
                fi
            fi
        fi
    done
}
total_of() {
    local sum="$INTRO" k d
    for k in $(seq 1 ${#SEG[@]}); do
        [ -s "$WORK/aud/$k.wav" ] || continue
        d="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$WORK/aud/$k.wav")"
        sum="$(awk "BEGIN{print $sum + $d + $PAUSE}")"
    done
    printf '%s' "$sum"
}

run_dub() {
    local WORK="/tmp/vdub_$$"; mkdir -p "$WORK/aud"; local LOG=/tmp/vdub_$$.log
    echo "[video_dub] start $(date '+%T')" > "$LOG"
    local Vd; Vd="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO")"

    mapfile -t SEG < <(printf '%s' "$TEXT" | tr '|' '\n')
    # 每段≤24字（=字幕最多两行）→ 逐段配音，字幕与语音一一对应（防错位）
    local -a _seg2=(); local _s _len _j
    for _s in "${SEG[@]}"; do
        _len="${#_s}"
        if [ "$_len" -le 24 ]; then _seg2+=("$_s")
        else for ((_j = 0; _j < _len; _j += 24)); do _seg2+=("${_s:_j:24}"); done; fi
    done
    SEG=("${_seg2[@]}")

    # 参考音频 → 临时克隆音色
    local TMPVOICE=""
    if [ -n "$REF" ] && [ "$REF" != "none" ]; then
        "$DIR/../../voice/cosyvoice.sh" add _vdub_tmp "$REF" >>"$LOG" 2>&1 && TMPVOICE="_vdub_tmp"
    fi
    local USE_VOICE="$VOICE"; [ -n "$TMPVOICE" ] && USE_VOICE="$TMPVOICE"

    # 配音 + 自动适配（超出视频时长则按比例精简各段并重录，至多迭代 4 次）
    tts_all
    local total; total="$(total_of)"
    local attempt=0 j factor cl newlen t
    while [ "$FIT" = "1" ] && awk "BEGIN{exit !($total > $Vd + 0.01)}" && [ "$attempt" -lt 4 ]; do
        attempt=$((attempt + 1))
        factor="$(awk "BEGIN{f=($Vd-1.5)/($total-1.5)*0.95; if(f>0.99)f=0.99; print f}")"
        echo "  · 超出（${total}s>${Vd}s），第 $attempt 次精简 ×${factor}" >>"$LOG"
        for j in $(seq 0 $((${#SEG[@]} - 1))); do
            t="${SEG[$j]}"; cl="${#t}"
            newlen="$(awk -v l="$cl" -v f="$factor" 'BEGIN{n=int(l*f); if(n<6)n=6; print n}')"
            SEG[$j]="${t:0:newlen}"
        done
        tts_all
        total="$(total_of)"
    done
    if awk "BEGIN{exit !($total > $Vd + 0.01)}"; then
        echo "自动精简后仍超出（约 ${total}s / 视频 ${Vd}s），请手工删减文案。" >&2
        [ -n "$TO" ] && "$DIR/wechat_send.sh" --to "$TO" "自动精简后仍超出视频时长（约 ${total}s / ${Vd}s），请删减文案。"
        rm -rf "$WORK"; [ -n "$TMPVOICE" ] && "$DIR/../../voice/cosyvoice.sh" del "$TMPVOICE" >/dev/null 2>&1
        return 1
    fi
    echo "  · 配音总时长 ${total}s / 视频 ${Vd}s（精简 ${attempt} 次）" >>"$LOG"

    # 仅测时长（不合成视频）
    if [ "$PROBE" = "1" ]; then
        echo "视频 ${Vd}s ｜ 配音 ${total}s ｜ 精简 ${attempt} 次 ｜ 段数 ${#SEG[@]}"
        local k2
        for k2 in $(seq 1 ${#SEG[@]}); do
            [ -s "$WORK/aud/$k2.wav" ] || continue
            printf '  段%d: %.2fs  %s\n' "$k2" "$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$WORK/aud/$k2.wav")" "${SEG[$((k2-1))]}"
        done
        rm -rf "$WORK"; [ -n "$TMPVOICE" ] && "$DIR/../../voice/cosyvoice.sh" del "$TMPVOICE" >/dev/null 2>&1
        return 0
    fi

    # ASS 字幕（3080 样式）
    local ASS="$WORK/sub.ass"
    {
        echo "[Script Info]"
        echo "Title: Video Dub"
        echo "ScriptType: v4.00+"
        echo "WrapStyle: 1"
        echo "ScaledBorderAndShadow: yes"
        echo "YCbCr Matrix: None"
        echo ""
        echo "[V4+ Styles]"
        echo "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding"
        echo "Style: $FONT_STYLE"
        echo ""
        echo "[Events]"
        echo "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
    } > "$ASS"

    local cur="$INTRO"
    for k in $(seq 1 ${#SEG[@]}); do
        [ -s "$WORK/aud/$k.wav" ] || continue
        local d
        d="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$WORK/aud/$k.wav")"
        emit_subs "$cur" "$d" "${SEG[$((k-1))]}"
        cur="$(awk "BEGIN{print $cur + $d + $PAUSE}")"
    done

    # 合并配音（段间 P 停顿），开头 INTRO 静音
    : > "$WORK/alist.txt"
    for k in $(seq 1 ${#SEG[@]}); do
        [ -s "$WORK/aud/$k.wav" ] || continue
        ffmpeg -y -i "$WORK/aud/$k.wav" -af "apad=pad_dur=$PAUSE" "$WORK/aud/pad_$k.wav" >>"$LOG" 2>&1 || true
        echo "file '$WORK/aud/pad_$k.wav'" >> "$WORK/alist.txt"
    done
    ffmpeg -y -f concat -safe 0 -i "$WORK/alist.txt" -c:a aac "$WORK/voice.aac" >>"$LOG" 2>&1 || true
    # 前置 INTRO 静音
    ffmpeg -y -f lavfi -t "$INTRO" -i anullsrc=r=24000:cl=mono "$WORK/sil.m4a" >>"$LOG" 2>&1 || true
    printf "file '%s'\nfile '%s'\n" "$WORK/sil.m4a" "$WORK/voice.aac" > "$WORK/final.txt"
    ffmpeg -y -f concat -safe 0 -i "$WORK/final.txt" -c:a aac "$WORK/narration.aac" >>"$LOG" 2>&1 || true

    # 合成：原视频画面 + 配音 + 字幕（配音短则保留全片；默认替换原声，--keep-audio 混音）
    local HAS_AUDIO
    HAS_AUDIO="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$VIDEO" | head -1)"
    if [ "$KEEPAUDIO" = "1" ] && [ -n "$HAS_AUDIO" ]; then
        ffmpeg -y -i "$VIDEO" -i "$WORK/narration.aac" \
            -filter_complex "[0:a]volume=0.35[a0];[1:a]volume=1.5[a1];[a0][a1]amix=inputs=2:duration=first:dropout_transition=2[aout]" \
            -map 0:v -map "[aout]" -vf "ass=$ASS" -c:v libx264 -c:a aac "$OUT" >>"$LOG" 2>&1 || true
    else
        ffmpeg -y -i "$VIDEO" -i "$WORK/narration.aac" -vf "ass=$ASS" -af "volume=1.5" \
            -map 0:v -map 1:a -c:v libx264 -c:a aac "$OUT" >>"$LOG" 2>&1 || true
    fi

    [ -n "$TMPVOICE" ] && "$DIR/../../voice/cosyvoice.sh" del "$TMPVOICE" >/dev/null 2>&1
    if [ -s "$OUT" ]; then
        echo "[video_dub] done -> $OUT" >> "$LOG"
        if [ "$NOSEND" = "0" ]; then
            if [ -n "$TO" ]; then "$DIR/wechat_send_file.sh" "$OUT" --to "$TO" >/dev/null 2>&1
            else "$DIR/wechat_send_file.sh" "$OUT" >/dev/null 2>&1; fi
        fi
    else
        echo "[video_dub] 合成失败" >> "$LOG"
    fi
    rm -rf "$WORK"
}

if [ "$FG" = "1" ] || [ "${VIDEO_DUB_RUN:-0}" = "1" ]; then
    run_dub
else
    setsid env VIDEO_DUB_RUN=1 bash "$0" "${ORIG_ARGS[@]}" </dev/null >/tmp/vdub_$$.out 2>&1 &
    echo "已后台开始配音+字幕，完成后文件在 $OUT${NOSEND:+（未发微信）}"
fi
