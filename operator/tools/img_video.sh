#!/usr/bin/env bash
# tools/img_video.sh — 出几张动漫图 → 合成带配音+字幕的动画短片（默认主题：中国传统童话）
# 出图用本机 backup.sh；配音 Kokoro 或克隆音色(CosyVoice3)；Ken Burns 运镜 + 白场转场 + 片名/结尾卡。
# @desc 动画短片：出图 → 配音+字幕+运镜/转场+片名卡 → 竖版短片（存 ~/image，默认不发微信）
# @usage tools/img_video.sh [--voice <音色名>] [--title 成语] [--pinyin KEZHOU] [--source 出处] [--end 释义] [--img-preset xhs|pyq] [--outimg 目录] [--imgdir 目录] [--size WxH] [--n 张数] [--scenes "分镜1|…"] [--text "旁白1|…"] [--out out.mp4] [--send [--to 会话]] [--fg]
# @rule **做动画短片 / 故事短片**：说“做个动画短片 / 用<成语/故事>生成动画短片 / 把 <故事> 做成动画”→ `tools/img_video.sh`。默认主题=**中国传统童话**。你可自己拟故事与分镜：`--scenes "分镜提示词1|分镜2|…"`、`--text "旁白1|旁白2|…"`（两者段数需一致；只复用已有图时只需 `--text`）。成语类可加 `--title <成语>`（片名长图，霜地国风）、`--pinyin <拼音>`、`--source <出处>`、`--end <释义>`（结尾卡）。出图默认 `--img-preset xhs`(1920×2560)/`pyq`(2048×2048)，`--outimg ~/image` 存图。克隆音色加 `--voice <名>`。**默认不发微信**——生成后用 `tools/wechat_send_file.sh <路径>` 再发（或加 `--send [--to 会话]`）；默认后台跑、立即返回。
# @order 16
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

BACKUP="${IMAGE_BACKUP:-/opt/static_comfyui/cpp/sd/backup.sh}"
. /opt/my-agent/voice/config.sh
FONT="${IMGVID_FONT:-/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc}"

TO=""; VOICE="${SAY_VOICE:-}"; N=""; SCENES=""; TEXTS=""; OUT=""; FG=0; NOSEND=1
TITLE=""; END=""; PYN=""; SRC=""
IMG_PRESET="${IMGVID_PRESET:-xhs}"; OUTIMG=""; IMGDIR=""
IW="${IMGVID_W:-1024}"; IH="${IMGVID_H:-1536}"; VW=1080; VH=1920; P=0.3
while [ $# -gt 0 ]; do
    case "$1" in
        --to)     TO="${2:-}"; NOSEND=0; shift 2 ;;
        --voice)  VOICE="${2:-}"; shift 2 ;;
        --n)      N="${2:-}"; shift 2 ;;
        --title)  TITLE="${2:-}"; shift 2 ;;
        --end)    END="${2:-}"; shift 2 ;;
        --pinyin) PYN="${2:-}"; shift 2 ;;
        --source) SRC="${2:-}"; shift 2 ;;
        --scenes) SCENES="${2:-}"; shift 2 ;;
        --text)   TEXTS="${2:-}"; shift 2 ;;
        --out)    OUT="${2:-}"; shift 2 ;;
        --size)   IW="${2%%x*}"; IH="${2##*x}"; IMG_PRESET="none"; shift 2 ;;
        --img-preset) IMG_PRESET="${2:-xhs}"; shift 2 ;;
        --outimg) OUTIMG="${2:-}"; shift 2 ;;
        --imgdir) IMGDIR="${2:-}"; shift 2 ;;
        --send)   NOSEND=0; shift ;;
        --no-send) NOSEND=1; shift ;;
        --fg)     FG=1; shift ;;
        *) shift ;;
    esac
done

# 默认故事：神笔马良
DEF_SCENES="anime style, a poor Chinese boy named Ma Liang drawing on the ground with a stick, ancient Chinese village|anime style, an old man with a white beard giving the boy a glowing magical paintbrush at night|anime style, the boy paints a cow and it comes alive and walks out of the painting, magical glow|anime style, the boy paints a waterwheel and farm tools for poor farmers, warm village scene|anime style, a greedy magistrate demanding gold, the boy paints a vast sea and a boat, dark cloudy sky|anime style, a great wind blows the greedy official's boat into the sea, dramatic waves"
DEF_TEXTS="从前有个穷孩子叫马良，他特别喜欢画画。|一天夜里，一位白胡子老爷爷送给他一支神笔。|马良画什么，什么就变成真的。|他给穷人们画耕牛和水车，帮大家过上好日子。|贪心的县官逼他画金山，马良就画了大海和一条船。|县官上了船，马良画起大风，把贪官卷进了大海。"

collect() { printf '%s' "$1" | tr '|' '\n'; }

# 字幕自动换行：优先按中文标点断句，单行 ≤ max 字（libass 用 \N）
wrap_text() {
    local t="$1" max="${2:-18}" out="" line="" seg
    while IFS= read -r seg; do
        [ -z "$seg" ] && continue
        while [ "${#seg}" -gt "$max" ]; do
            [ -n "$line" ] && { out="${out:+$out\\N}$line"; line=""; }
            out="${out:+$out\\N}${seg:0:$max}"; seg="${seg:$max}"
        done
        if [ -z "$line" ]; then line="$seg"
        elif [ $(( ${#line} + ${#seg} )) -le "$max" ]; then line="$line$seg"
        else out="${out:+$out\\N}$line"; line="$seg"; fi
    done < <(printf '%s' "$t" | sed -E 's/([，。！？、；：])/\1\n/g')
    [ -n "$line" ] && out="${out:+$out\\N}$line"
    printf '%s' "$out"
}

# 生成卡片（片名/结尾）1080x1920，中国传统配色（霜地·墨色·黛蓝·朱砂）
seal_png() { # $1=out 朱砂印章
    convert -size 150x150 xc:'#E2F0CB' -fill '#D92121' -draw 'roundrectangle 6,6 144,144 16,16' \
        -font "$FONT" -fill white -pointsize 46 -gravity center -annotate +0+0 "$2" "$1"
}
make_title_card() { # $1=out
    local t="$1" id="$TITLE" l1 l2
    if [ "${#id}" -eq 4 ]; then l1="${id:0:2}"; l2="${id:2:2}"; else l1="$id"; l2=""; fi
    convert -size ${VW}x${VH} gradient:'#F6FAEC'-'#E2F0CB' \
        -stroke '#C4D6A6' -strokewidth 6 -fill none -draw "rectangle 52,52 $((VW-52)),$((VH-52))" \
        -font "$FONT" -stroke none \
        -fill '#2E8B57' -pointsize 42 -gravity north -annotate +0+150 "中 国 传 统 成 语 故 事" \
        -stroke '#C4D6A6' -strokewidth 3 -draw "line 400,300 680,300" -stroke none \
        -fill '#1D1B1C' -pointsize 210 -gravity center -annotate +0-130 "$l1" \
        -fill '#1D1B1C' -pointsize 210 -annotate +0+120 "${l2:-　}" \
        -fill '#2A3C5C' -pointsize 48 -annotate +0+360 "${PYN:-　}" \
        -stroke '#2A3C5C' -strokewidth 3 -draw "line 360,1200 720,1200" -stroke none \
        -fill '#5a6b4f' -pointsize 34 -gravity south -annotate +0+150 "${SRC:-　}" \
        "$t"
    seal_png "$WORK_SEAL" "成语"
    convert "$t" "$WORK_SEAL" -gravity southeast -geometry +90+150 -composite "$t"
}
make_end_card() { # $1=out
    convert -size ${VW}x${VH} gradient:'#F6FAEC'-'#E2F0CB' \
        -stroke '#C4D6A6' -strokewidth 6 -fill none -draw "rectangle 52,52 $((VW-52)),$((VH-52))" \
        -font "$FONT" \
        \( -background none -fill '#8C2B22' -pointsize 130 -size 900x -gravity center label:"$TITLE" \) -gravity north -geometry +0+300 -composite \
        -stroke '#C4D6A6' -strokewidth 3 -draw "line 400,560 680,560" \
        \( -background none -fill '#2A3C5C' -pointsize 56 -size 860x -gravity center caption:"${END:-}" \) -gravity center -geometry +0+0 -composite \
        -stroke none -fill '#5a6b4f' -pointsize 36 -gravity south -annotate +0+150 "中国成语故事" \
        "$1"
}

if [ -n "$TEXTS" ]; then
    mapfile -t T_ARRAY < <(collect "$TEXTS")
    if [ -n "$SCENES" ]; then mapfile -t S_ARRAY < <(collect "$SCENES"); else S_ARRAY=(); fi
else
    mapfile -t S_ARRAY < <(collect "$DEF_SCENES")
    mapfile -t T_ARRAY < <(collect "$DEF_TEXTS")
fi
if [ -n "$N" ] && [ "$N" -gt 0 ] 2>/dev/null; then
    [ "${#T_ARRAY[@]}" -gt "$N" ] && T_ARRAY=("${T_ARRAY[@]:0:$N}")
    [ "${#S_ARRAY[@]}" -gt "$N" ] && S_ARRAY=("${S_ARRAY[@]:0:$N}")
fi
CNT="${#T_ARRAY[@]}"
[ "$CNT" -gt 0 ] || { echo "没有旁白文案" >&2; exit 2; }
if [ -z "$IMGDIR" ] && [ "${#S_ARRAY[@]}" -ne "$CNT" ]; then
    echo "分镜/旁白段数不一致（${#S_ARRAY[@]} vs $CNT）" >&2; exit 2
fi
[ -n "$OUT" ] || OUT="$HOME/image/动画短片_$(date +%Y%m%d_%H%M%S).mp4"
if [ -n "$IMGDIR" ]; then IMGSRC_DESC="复用 $IMGDIR"; else IMGSRC_DESC="preset=$IMG_PRESET"; fi
echo "分镜 $CNT 段，配音=${VOICE:-Kokoro}，出图=${IMGSRC_DESC}，${TITLE:+片名卡「$TITLE」}，视频 ${VW}x${VH}，输出 $OUT"
[ -x "$BACKUP" ] || { echo "backup.sh 不存在: $BACKUP" >&2; exit 1; }

run_pipeline() {
    local WORK="/tmp/imgvideo_$$"; mkdir -p "$WORK/img" "$WORK/aud" "$WORK/seg"
    local LOG=/tmp/imgvideo_$$.log
    echo "[img_video] start $(date '+%T')" > "$LOG"

    # 1) 场景图：复用或出图
    local -a SCENE_IMG=()
    if [ -n "${IMGDIR:-}" ] && [ -d "$IMGDIR" ]; then
        while IFS= read -r f; do [ -n "$f" ] && SCENE_IMG+=("$f"); done \
            < <(find "$IMGDIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | sort -V)
        echo "  · 复用已有图 ${#SCENE_IMG[@]} 张: $IMGDIR" >> "$LOG"
    fi
    if [ "${#SCENE_IMG[@]}" -lt "$CNT" ]; then
        local dest="$WORK/img"; [ -n "${OUTIMG:-}" ] && { mkdir -p "$OUTIMG"; dest="$OUTIMG"; }
        SCENE_IMG=()
        local i=0
        for i in $(seq 0 $((CNT-1))); do
            local outpng="$dest/scene_$(printf '%02d' "$i").png"
            echo "  · 出图 $((i+1))/$CNT ..." >> "$LOG"
            if [ -n "${IMG_PRESET:-}" ] && [ "$IMG_PRESET" != "none" ]; then
                "$BACKUP" "${S_ARRAY[$i]}" "$outpng" --preset "$IMG_PRESET" >>"$LOG" 2>&1 || true
            else
                "$BACKUP" "${S_ARRAY[$i]}" "$outpng" "$IW" "$IH" >>"$LOG" 2>&1 || true
            fi
            local got
            got="$(sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -oE 'File:[[:space:]]+/[^[:space:]]+\.png' | tail -1 | sed -E 's/^File:[[:space:]]+//')"
            if [ -n "$got" ] && [ -f "$got" ] && [ "$got" != "$outpng" ]; then mv -f "$got" "$outpng" 2>/dev/null; fi
            [ -f "$outpng" ] || { echo "出图失败(第 $((i+1)) 张)，中止" >> "$LOG"; finish_fail "$LOG"; return 1; }
            SCENE_IMG+=("$outpng")
        done
    fi

    # 2) 组装片段序列：片名卡 + 场景 + 结尾卡
    local -a SEG_IMG=() SEG_TXT=()
    local WORK_SEAL="$WORK/img/seal.png"
    if [ -n "$TITLE" ]; then
        make_title_card "$WORK/img/title.png" >>"$LOG" 2>&1
        SEG_IMG+=("$WORK/img/title.png"); SEG_TXT+=("$TITLE")
    fi
    local k
    for k in $(seq 0 $((CNT-1))); do SEG_IMG+=("${SCENE_IMG[$k]}"); SEG_TXT+=("${T_ARRAY[$k]}"); done
    if [ -n "$TITLE" ]; then
        make_end_card "$WORK/img/end.png" >>"$LOG" 2>&1
        SEG_IMG+=("$WORK/img/end.png"); SEG_TXT+=("${END:-}")
    fi
    local NALL="${#SEG_TXT[@]}"

    # 3) 逐段配音
    local j
    for j in $(seq 0 $((NALL-1))); do
        local wav="$WORK/aud/$((j+1)).wav" textx="${SEG_TXT[$j]}"
        [ -z "$textx" ] && textx="　"
        if [ -n "$VOICE" ] && [ -f "$VOICES_DIR/$VOICE.gguf" ]; then
            "$DIR/../voice/cosyvoice.sh" synth "$VOICE" "$textx" "$wav" >>"$LOG" 2>&1 || true
        fi
        if [ ! -s "$wav" ]; then
            LD_LIBRARY_PATH="${SHERPA_LIB}:${LD_LIBRARY_PATH:-}" "$SHERPA_BIN" \
                --kokoro-model="$KOKORO_DIR/model.onnx" --kokoro-voices="$KOKORO_DIR/voices.bin" \
                --kokoro-tokens="$KOKORO_DIR/tokens.txt" --kokoro-data-dir="$KOKORO_DIR/espeak-ng-data" \
                --kokoro-lexicon="$KOKORO_DIR/lexicon-us-en.txt,$KOKORO_DIR/lexicon-zh.txt" \
                --tts-rule-fsts="$KOKORO_DIR/date-zh.fst,$KOKORO_DIR/number-zh.fst" \
                --num-threads="${TTS_THREADS:-4}" --sid="${KOKORO_SID:-47}" \
                --output-filename="$wav" "$textx" >>"$LOG" 2>&1 || true
        fi
        if [ ! -s "$wav" ]; then   # 无音频则造 2s 静音
            ffmpeg -y -f lavfi -i anullsrc=r=24000:cl=mono -t 2 "$wav" >>"$LOG" 2>&1 || true
        fi
    done

    # 4) ASS 字幕（按配音时长+停顿）
    local ASS="$WORK/sub.ass"
    cat > "$ASS" <<ASS
[Script Info]
ScriptType: v4.00+
PlayResX: ${VW}
PlayResY: ${VH}
WrapStyle: 2
ScaledBorderAndShadow: yes
YCbCr Format: None

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,WenQuanYi Zen Hei,46,&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,3,2,2,70,70,150,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
ASS
    local t=0 k wtext
    for k in $(seq 0 $((NALL-1))); do
        local dur st en
        dur="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$WORK/aud/$((k+1)).wav")"
        dur="$(awk "BEGIN{print $dur+$P}")"
        st="$(awk "BEGIN{printf \"0:%02d:%05.2f\", int($t/60), $t%60}")"
        en="$(awk "BEGIN{printf \"0:%02d:%05.2f\", int(($t+$dur)/60), ($t+$dur)%60}")"
        wtext="$(wrap_text "${SEG_TXT[$k]}" 18)"
        [ -n "$wtext" ] && printf 'Dialogue: 0,%s,%s,Default,,0,0,0,,%s\n' "$st" "$en" "$wtext" >> "$ASS"
        t="$(awk "BEGIN{print $t+$dur}")"
    done

    # 5) 图片 → 片段（Ken Burns 运镜 + 白场淡入淡出）
    local m=0 frames c cint
    for m in $(seq 0 $((NALL-1))); do
        local aud c dur zexpr
        aud="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$WORK/aud/$((m+1)).wav")"
        c="$(awk "BEGIN{print $aud+$P}")"; cint="$(awk "BEGIN{print int($c*25)}")"
        if [ $((m % 2)) -eq 0 ]; then
            zexpr="min(zoom+0.0009,1.13)"        # 推近
        else
            zexpr="if(eq(on,1),1.13,max(zoom-0.0009,1.0))"  # 拉远
        fi
        ffmpeg -y -i "${SEG_IMG[$m]}" -vf \
          "scale=$((VW*2)):$((VH*2)):force_original_aspect_ratio=increase,crop=$((VW*2)):$((VH*2)),zoompan=z='$zexpr':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=$cint:s=${VW}x${VH}:fps=25,fade=t=in:st=0:d=0.25:color=white,fade=t=out:st=$(awk "BEGIN{print $c-0.3}"):d=0.3:color=white,format=yuv420p" \
          -t "$c" -r 25 "$WORK/seg/seg_$m.mp4" >>"$LOG" 2>&1 || true
        [ -s "$WORK/seg/seg_$m.mp4" ] || { echo "片段失败 $((m+1))" >> "$LOG"; finish_fail "$LOG"; return 1; }
    done
    : > "$WORK/concat.txt"
    for f in $(ls "$WORK"/seg/seg_*.mp4 2>/dev/null | sort -V); do echo "file '$f'" >> "$WORK/concat.txt"; done
    ffmpeg -y -f concat -safe 0 -i "$WORK/concat.txt" -c copy "$WORK/video.mp4" >>"$LOG" 2>&1 || true

    # 6) 配音拼接（每段后 P 秒静音）
    : > "$WORK/aud.txt"
    local p
    for p in $(seq 1 $NALL); do
        ffmpeg -y -i "$WORK/aud/$p.wav" -af "apad=pad_dur=$P" "$WORK/aud/pad_$p.wav" >>"$LOG" 2>&1 || true
        echo "file '$WORK/aud/pad_$p.wav'" >> "$WORK/aud.txt"
    done
    ffmpeg -y -f concat -safe 0 -i "$WORK/aud.txt" -c:a aac "$WORK/audio.aac" >>"$LOG" 2>&1 || true

    # 7) 合成 + 烧字幕
    ffmpeg -y -i "$WORK/video.mp4" -i "$WORK/audio.aac" -vf "ass=$ASS" \
        -map 0:v -map 1:a -c:v libx264 -c:a aac -shortest "$OUT" >>"$LOG" 2>&1 || true

    if [ -s "$OUT" ]; then
        echo "[img_video] done -> $OUT" >> "$LOG"
        if [ "$NOSEND" = "1" ]; then echo "[img_video] --no-send：跳过发微信" >> "$LOG"
        elif [ -n "$TO" ]; then "$DIR/wechat_send_file.sh" "$OUT" --to "$TO" >/dev/null 2>&1
        else "$DIR/wechat_send_file.sh" "$OUT" >/dev/null 2>&1; fi
    else
        echo "[img_video] 合成失败" >> "$LOG"
    fi
    rm -rf "$WORK"
}

finish_fail() {
    local msg="动画短片生成失败，日志尾部：\n$(tail -n 8 "$1" 2>/dev/null)"
    echo -e "$msg" >&2
    [ "$NOSEND" = "1" ] && return 0
    if [ -n "$TO" ]; then "$DIR/wechat_send.sh" --to "$TO" "$msg" >/dev/null 2>&1
    else "$DIR/wechat_send.sh" "$msg" >/dev/null 2>&1; fi
}

if [ "$FG" = "1" ] || [ "${IMGVIDEO_RUN:-0}" = "1" ]; then
    run_pipeline
else
    setsid env IMGVIDEO_RUN=1 bash "$0" "$@" </dev/null >/tmp/imgvideo_$$.out 2>&1 &
    if [ "$NOSEND" = "1" ]; then
        echo "已后台开始生成动画短片（每张图约数分钟），完成后文件在 $OUT（未发微信；发送用 wechat_send_file.sh）"
    else
        echo "已后台开始生成动画短片，完成后发送到微信${TO:+「$TO」}"
    fi
fi
