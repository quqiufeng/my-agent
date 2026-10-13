#!/usr/bin/env bash
# tools/lora.sh — 训练 Z-Image LoRA（一条龙）：建数据集 → 预缓存 → 训练 → 转换 → 注册触发词 → 出样图发微信
# @desc 用一批图片训练 Z-Image LoRA；**写真/整体(style)** 与 **人脸(face)** 两种，可 `--both` 一遍出两个（图片处理两遍、先后训练）；图片来源=本地目录/微博搜索/微博相册；后台一条龙，完成发微信（样图+文件名）
# @usage tools/lora.sh train (<图片目录> | --weibo <明星/关键词> | --album <昵称/uid>) <触发词> [--mode style|face|both] [--rank N] [--epochs N] [--res 512|1536] [--pages N|all] [--limit N] [--to 会话] [--force] | status | list | cancel
# @rule **训练 LoRA**：说“用这些图训个 LoRA / 训练一个 LoRA / 训个写真(整体) LoRA / 训个人脸(身份) LoRA / 用某人的微博图训 LoRA”→ `tools/lora.sh train <图片来源> <触发词> [--mode style|face|both]`。**图片来源三选一**：本地目录 / `--weibo <明星|关键词>`（微博搜索图）/ `--album <昵称|uid>`（微博相册大图，同一人海量图）。**mode**：`style`=写真/整体（缩放到合适大小→检测写真人像→打标）；`face`=人脸（扣人脸→打标）；**`both`=图片处理两遍、先后训练两个 LoRA**（写真触发词=`<触发词>`，人脸触发词=`<触发词>_face`）——**用某人的微博图既训写真又训人脸就用 `--both`**。抓图+处理+训练全在**后台**跑、脚本立即返回；每个 LoRA 训完自动发微信（样图+文件名）。问进度 → `lora.sh status`；看已有 → `lora.sh list`；停 → `lora.sh cancel`。GPU 忙会被拒绝（加 `--force` 强跑）。
# @order 9
# 用法:
#   tools/lora.sh train <图片目录> <触发词> [--mode style|face|both] [--rank 16|32] [--epochs 8] [--sample-prompt "..."] [--to 会话] [--force]
#   tools/lora.sh train --album <昵称|uid> <触发词> --mode both [--pages 5|all] [--limit 60]   # 微博相册→先写真后人脸，两个 LoRA
#   tools/lora.sh train --weibo <明星|关键词> <触发词> --mode style [--pages 3]               # 微博搜索→写真/整体 LoRA
#   tools/lora.sh status [触发词]      # 看训练进度（不传=最近一个任务）
#   tools/lora.sh list                # 列出已训练的 LoRA + 触发词
#   tools/lora.sh cancel [触发词]      # 停止当前/指定训练
# 说明: 复用 /opt/static_comfyui/train_lora 的脚本（make_face_dataset / prepare_dataset / musubi_train）；
#   微博图片来源复用 weibo_album.sh / weibo_imgs.sh（先抓到 /data/datasets/_src/<触发词>/ 再训练）。
#   产物: /data/lora/<触发词>/<触发词>_sdcpp.safetensors；触发词写入 /data/lora/lora_triggers.conf，
#   之后 tools/image.sh "提示词" 出图会自动带该触发词（也可显式 --lora <路径>:0.7）。
#   人脸模式要求是同一个人、清晰、多角度；微博相册天然是同一人，最合适。
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

SC=/opt/static_comfyui
TL="$SC/train_lora"
PYPREP=/data/venv/bin/python
PYM=/data/venv-musubi/bin
MUSUBI=/opt/musubi-tuner/src/musubi_tuner
VAE=/data/models/z-image-turbo/vae/diffusion_pytorch_model.safetensors
TE=/data/models/z-image-te-qwen3.safetensors
DIT=/data/models/z-image-base/transformer/diffusion_pytorch_model-00001-of-00002.safetensors
LORADIR=/data/lora
TRIGGERS="$LORADIR/lora_triggers.conf"
JOBS="$LORADIR/.jobs"
GPU_MIN_FREE="${LORA_GPU_MIN_FREE:-6000}"   # 训练前要求的最小空闲显存(MiB)

notify() { # $1=文本 [$2=会话]
    if [ -n "${2:-}" ]; then "$DIR/wechat_send.sh" --to "$2" "$1" >/dev/null 2>&1
    else "$DIR/wechat_send.sh" "$1" >/dev/null 2>&1; fi
}
notify_file() { # $1=文件 [$2=会话]
    [ -f "${1:-}" ] || return 0
    if [ -n "${2:-}" ]; then "$DIR/wechat_send_file.sh" "$1" --to "$2" >/dev/null 2>&1
    else "$DIR/wechat_send_file.sh" "$1" >/dev/null 2>&1; fi
}
latest_job() { ls -dt "$JOBS"/*/ 2>/dev/null | head -1; }

# ---------------------------------------------------------------------------
cmd_train() {
    local SRCKIND="" SRCARG="" TRIGGER="" MODE="style" RANK="" EPOCHS="" RES="" TO="" FORCE=0 SAMPLE_PROMPT="" PAGES="" LIMIT=""
    local POS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --mode)          MODE="${2:-}"; shift 2 ;;
            --rank|--dim)    RANK="${2:-}"; shift 2 ;;
            --epochs)        EPOCHS="${2:-}"; shift 2 ;;
            --res)           RES="${2:-}"; shift 2 ;;
            --sample-prompt) SAMPLE_PROMPT="${2:-}"; shift 2 ;;
            --to)            TO="${2:-}"; shift 2 ;;
            --force)         FORCE=1; shift ;;
            --face)          MODE=face; shift ;;
            --style)         MODE=style; shift ;;
            --both)          MODE=both; shift ;;
            --weibo)         SRCKIND=weibo; SRCARG="${2:-}"; shift 2 ;;
            --album)         SRCKIND=album; SRCARG="${2:-}"; shift 2 ;;
            --pages)         PAGES="${2:-}"; shift 2 ;;
            --limit)         LIMIT="${2:-}"; shift 2 ;;
            -*)              shift ;;
            *)               POS+=("$1"); shift ;;
        esac
    done
    if [ -z "$SRCKIND" ]; then SRCKIND=dir; SRCARG="${POS[0]:-}"; TRIGGER="${POS[1]:-}"; else TRIGGER="${POS[0]:-}"; fi

    [ -n "$TRIGGER" ] || { echo "缺少「触发词」（英文/数字，如 mystyle / celebA）" >&2; exit 2; }
    case "$TRIGGER" in *[!A-Za-z0-9_-]*) echo "触发词只能含字母/数字/下划线/连字符: $TRIGGER" >&2; exit 2 ;; esac
    case "$MODE" in style|face|both) ;; *) echo "--mode 只能是 style(写真/整体) / face(人脸) / both(两遍都训)" >&2; exit 2 ;; esac

    local n=0
    case "$SRCKIND" in
        dir)
            SRCARG="${SRCARG/#\~/$HOME}"
            [ -n "$SRCARG" ] || { echo "缺少「图片目录」。用法: lora.sh train <图片目录> <触发词> | train --weibo/--album <名字> <触发词>" >&2; exit 2; }
            [ -d "$SRCARG" ] || { echo "图片目录不存在: $SRCARG" >&2; exit 2; }
            n="$(find "$SRCARG" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | wc -l | tr -d ' ')"
            [ "${n:-0}" -ge 5 ] || { echo "图片太少（$n 张，建议 ≥15，人脸 20~50）: $SRCARG" >&2; exit 2; }
            ;;
        weibo|album)
            [ -n "$SRCARG" ] || { echo "--$SRCKIND 需要「明星/关键词 或 昵称/uid」" >&2; exit 2; }
            # 微博 cookie 预检（快速失败）
            if [ -z "${WEIBO_COOKIE:-}" ] && ! sed -n 's/^WEIBO_COOKIE=//p' "$HOME/.env" 2>/dev/null | head -1 | grep -q . \
               && [ ! -s "${WEIBO_COOKIE_FILE:-$HOME/.myagent_weibo_cookie}" ]; then
                echo "没有微博 cookie。先跑一次: tools/weibo_imgs.sh --refresh-cookie（需已登录 Chrome）" >&2; exit 3
            fi
            ;;
    esac

    # 已有任务在跑则拒绝（避免抢显存）
    for d in "$JOBS"/*/; do
        [ -d "$d" ] || continue
        local p; p="$(cat "$d/pid" 2>/dev/null)"
        [ -n "$p" ] && kill -0 "$p" 2>/dev/null && { echo "已有训练在运行（$(basename "$d")，pid $p）。先 lora.sh status / cancel。" >&2; exit 3; }
    done

    if command -v nvidia-smi >/dev/null 2>&1 && [ "$FORCE" != "1" ]; then
        local free; free="$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')"
        if [ -n "${free:-}" ] && [ "$free" -lt "$GPU_MIN_FREE" ]; then
            echo "GPU 空闲显存偏低（${free} MiB < ${GPU_MIN_FREE}）。稍后再试或加 --force。" >&2; exit 3
        fi
    fi

    mkdir -p "$JOBS"
    local JOBDIR="$JOBS/$TRIGGER"
    rm -rf "$JOBDIR"; mkdir -p "$JOBDIR"
    local LOG="$JOBDIR/train.log"

    setsid "$DIR/lora.sh" __run "$SRCKIND" "$SRCARG" "$TRIGGER" "$MODE" "$RANK" "$EPOCHS" "$RES" "$SAMPLE_PROMPT" "$TO" "$PAGES" "$LIMIT" \
        > "$LOG" 2>&1 < /dev/null &
    sleep 1
    case "$SRCKIND" in
        dir)   echo "已开始训练 LoRA「$TRIGGER」（mode=$MODE，图片 $n 张）" ;;
        weibo) echo "已开始：抓微博图「$SRCARG」→ 训练 LoRA「$TRIGGER」（mode=$MODE）" ;;
        album) echo "已开始：抓微博相册「$SRCARG」→ 训练 LoRA「$TRIGGER」（mode=$MODE）" ;;
    esac
    [ "$MODE" = both ] && echo "模式=both：两遍（①缩放到合适大小+写真人像检测→写真/整体 LoRA；②扣人脸→人脸 LoRA），先后训练"
    echo "任务目录: $JOBDIR"
    echo "日志: $LOG"
    echo "查看进度: tools/lora.sh status $TRIGGER"
}

# ---------------------------------------------------------------------------
cmd_run() {
    local SRCKIND="$1" SRCARG="$2" TRIGGER="$3" MODE="${4:-style}" RANK="$5" EPOCHS="$6" RES="$7" \
          SAMPLE_PROMPT="$8" TO="$9" PAGES="${10:-}" LIMIT="${11:-}"
    local JOBDIR="$JOBS/$TRIGGER"
    mkdir -p "$JOBDIR"
    echo $$ > "$JOBDIR/pid"

    log() { echo "[$(date '+%F %T')] $*"; }
    fail() { log "✗ 失败: $*"; notify "LoRA 训练失败（$TRIGGER）：$*" "$TO"; exit 1; }

    # 解析图片来源：本地目录 / 微博搜索 / 微博相册
    local SRC
    if [ "$SRCKIND" = dir ]; then
        SRC="$SRCARG"
    else
        local STAGE="/data/datasets/_src/$TRIGGER"
        rm -rf "$STAGE"; mkdir -p "$STAGE"
        local _pages _limit; _limit="${LIMIT:-100}"
        if [ "$SRCKIND" = album ]; then _pages="${PAGES:-5}"; else _pages="${PAGES:-3}"; fi
        log ">>> 抓微博图（$SRCKIND $SRCARG pages=$_pages limit=$_limit）"
        if [ "$SRCKIND" = album ]; then
            "$DIR/weibo_album.sh" "$SRCARG" "$_pages" --save "$STAGE" --limit "$_limit" || fail "微博相册抓取失败"
        else
            "$DIR/weibo_imgs.sh" "$SRCARG" "$_pages" --save "$STAGE" --limit "$_limit" || fail "微博搜索抓取失败"
        fi
        SRC="$STAGE"
    fi
    log "图片来源: $SRC  mode=$MODE  trigger=$TRIGGER"

    case "$MODE" in
      both)
        log "===== 第一遍：写真(整体) LoRA「${TRIGGER}」（缩放→写真人像检测→打标→训练；合格图存 $SRC/style）====="
        build_one "$SRC" "${TRIGGER}" style "${RANK:-16}" "${EPOCHS:-8}" "${RES:-1536}" "$SAMPLE_PROMPT" "$TO" "$JOBDIR" "$SRC/style" 1 "" \
            || fail "写真 LoRA 失败(step $?)"
        log "===== 第二遍：人脸 LoRA「${TRIGGER}_face」（基于 $SRC/style/images → 扣脸→打标→训练；合格图存 $SRC/face）====="
        build_one "$SRC/style/images" "${TRIGGER}_face" face "${FACE_RANK:-32}" "${FACE_EPOCHS:-12}" 512 "$SAMPLE_PROMPT" "$TO" "$JOBDIR" "$SRC/face" 0 "$SRC" \
            || fail "人脸 LoRA 失败(step $?)"
        ;;
      face)
        build_one "$SRC" "$TRIGGER" face "${RANK:-32}" "${EPOCHS:-12}" 512 "$SAMPLE_PROMPT" "$TO" "$JOBDIR" "$SRC/face" 1 "$SRC" \
            || fail "人脸 LoRA 失败(step $?)"
        ;;
      *)
        build_one "$SRC" "$TRIGGER" style "${RANK:-16}" "${EPOCHS:-8}" "${RES:-1536}" "$SAMPLE_PROMPT" "$TO" "$JOBDIR" "$SRC/style" 1 "" \
            || fail "写真 LoRA 失败(step $?)"
        ;;
    esac
    log "[done]"
}

# 单个 LoRA 全流程：数据集(检测筛→统一尺寸→打标) → 预缓存 → 训练 → 注册触发词 → 样图发微信
# 参数: src trigger mode rank epochs res sample_prompt to jobdir
build_one() {
    local SRC="$1" T="$2" MODE="$3" RANK="$4" EPOCHS="$5" RES="$6" SAMPLE_PROMPT="$7" TO="$8" JOBDIR="$9" DEST="${10:-}" RMSRC="${11:-0}" LORADEST="${12:-}"
    local DS OUT LORA
    DS="${DEST:-/data/datasets/${T}_${MODE}}"
    OUT="$LORADIR/$T"

    # 数据集目录存在（有 dataset.toml + images）→ 直接复用，跳过处理
    if [ -f "$DS/dataset.toml" ] && [ -n "$(ls -A "$DS/images" 2>/dev/null)" ]; then
        log ">>> [$MODE/$T] 复用已有数据集（跳过处理）: $DS"
    else
        log ">>> [$MODE/$T] 数据集：检测筛 → 统一尺寸 → 自然语言打标  -> $DS"
        local RARG=(); [ "$RMSRC" = "1" ] && RARG=(--rm-rejected --rm-source)
        "$PYPREP" "$TL/curate_dataset.py" "$SRC" "$DS" "$T" --mode "$MODE" --res "$RES" --crop 512 "${RARG[@]}" || return 1
        [ -f "$DS/dataset.toml" ] || return 2
    fi

    log ">>> [$MODE/$T] 预缓存 latent + 文本编码器"
    "$PYM/python" "$MUSUBI/zimage_cache_latents.py" --dataset_config "$DS/dataset.toml" \
        --vae "$VAE" --device cuda || return 3
    "$PYM/python" "$MUSUBI/zimage_cache_text_encoder_outputs.py" --dataset_config "$DS/dataset.toml" \
        --text_encoder "$TE" --batch_size 8 --device cuda || return 4

    log ">>> [$MODE/$T] 训练（musubi-tuner）"
    local BLOCKS=12; [ "$MODE" = face ] && BLOCKS=0    # 1536 必须换出(BLOCKS=12，自动算的8会OOM)；512 充裕不换出
    DIT="$DIT" FP8=0 BLOCKS="$BLOCKS" DIM="$RANK" EPOCHS="$EPOCHS" DATA="$DS" OUT="$OUT" OUT_NAME="$T" \
        bash "$TL/musubi_train.sh" || return 5

    LORA="$OUT/${T}_sdcpp.safetensors"
    [ -f "$LORA" ] || LORA="$(ls "$OUT"/*_sdcpp.safetensors 2>/dev/null | head -1)"
    [ -n "${LORA:-}" ] && [ -f "$LORA" ] || return 6

    mkdir -p "$LORADIR"; touch "$TRIGGERS"
    grep -qF "$(basename "$LORA") = " "$TRIGGERS" || echo "$(basename "$LORA") = $T" >> "$TRIGGERS"

    # 把 LoRA 另存到指定目录（如：face LoRA 存到图片源目录）
    if [ -n "$LORADEST" ] && [ -d "$LORADEST" ]; then
        cp -f "$LORA" "$LORADEST/$(basename "$LORA")" && log "LoRA 已保存到源目录: $LORADEST/$(basename "$LORA")"
    fi

    local SAMPLE="$OUT/${T}_sample_$(date +%Y%m%d_%H%M%S).png"
    if [ -n "$SAMPLE_PROMPT" ]; then
        "$SC/cpp/sd/backup.sh" "$SAMPLE_PROMPT" "$SAMPLE" 1440 1440 --lora "$LORA:0.7" > "$JOBDIR/sample_$T.log" 2>&1
    else
        "$SC/cpp/sd/backup.sh" "$SAMPLE" 1440 1440 --lora "$LORA:0.7" > "$JOBDIR/sample_$T.log" 2>&1
    fi
    [ -f "$SAMPLE" ] || SAMPLE="$(sed 's/\x1b\[[0-9;]*m//g' "$JOBDIR/sample_$T.log" 2>/dev/null | grep -oE '/[^ ]+\.png' | tail -1)"
    [ -f "${SAMPLE:-}" ] || SAMPLE=""

    log "✓ 完成: $LORA"
    notify "LoRA 训练完成 ✅ [$MODE]
触发词: $T
文件: $(basename "$LORA")
出图: image.sh \"提示词\"（自动带触发词），或 --lora $LORA:0.7" "$TO"
    [ -n "$SAMPLE" ] && notify_file "$SAMPLE" "$TO"
    notify_file "$LORA" "$TO"

    STYLE_IMAGES="$DS/images"   # 供 both 第二遍取「第一遍处理完的图」
    return 0
}

# ---------------------------------------------------------------------------
cmd_status() {
    local TRIGGER="${1:-}" JOBDIR
    if [ -n "$TRIGGER" ]; then JOBDIR="$JOBS/$TRIGGER"; else JOBDIR="$(latest_job)"; fi
    [ -d "$JOBDIR" ] || { echo "没有训练任务"; exit 0; }
    local PID; PID="$(cat "$JOBDIR/pid" 2>/dev/null)"
    echo "任务: $(basename "$JOBDIR")"
    echo "目录: $JOBDIR"
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then echo "状态: 运行中 (pid $PID)"; else echo "状态: 已结束"; fi
    echo "--- 日志尾部 ---"
    tail -n 25 "$JOBDIR/train.log" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
}

cmd_list() {
    echo "已有 LoRA（$LORADIR）:"
    local found=0
    for d in "$LORADIR"/*/; do
        [ -d "$d" ] || continue
        local b; b="$(basename "$d")"; [ "$b" = ".jobs" ] && continue
        local f; f="$(ls "$d"*_sdcpp.safetensors 2>/dev/null | head -1)"
        [ -n "$f" ] || continue
        echo "  • $b -> $(basename "$f")  ($(du -h "$f" 2>/dev/null | cut -f1))"; found=1
    done
    [ "$found" = 0 ] && echo "  (无)"
    echo "--- 触发词映射（$TRIGGERS）---"
    cat "$TRIGGERS" 2>/dev/null || echo "  (无)"
}

cmd_cancel() {
    local TRIGGER="${1:-}" JOBDIR
    if [ -n "$TRIGGER" ]; then JOBDIR="$JOBS/$TRIGGER"; else JOBDIR="$(latest_job)"; fi
    [ -d "$JOBDIR" ] || { echo "没有训练任务"; exit 0; }
    local PID; PID="$(cat "$JOBDIR/pid" 2>/dev/null)"
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill -TERM -"$PID" 2>/dev/null || kill -TERM "$PID" 2>/dev/null
        sleep 1; kill -KILL -"$PID" 2>/dev/null || kill -KILL "$PID" 2>/dev/null
        echo "已停止训练: $(basename "$JOBDIR") (pid $PID)"
    else
        echo "任务已结束: $(basename "$JOBDIR")"
    fi
}

# ---------------------------------------------------------------------------
case "${1:-}" in
    train)  shift; cmd_train "$@" ;;
    status) shift; cmd_status "${1:-}" ;;
    list)   cmd_list ;;
    cancel) shift; cmd_cancel "${1:-}" ;;
    __run)  shift; cmd_run "$@" ;;
    *) echo "用法: tools/lora.sh train <图片目录> <触发词> [--mode style|face] [--rank N] [--epochs N] [--res 512|1536] [--to 会话] [--force] | status | list | cancel" >&2; exit 2 ;;
esac
