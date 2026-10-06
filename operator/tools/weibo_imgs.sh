#!/usr/bin/env bash
# tools/weibo_imgs.sh — 看某明星微博图：用已登录 Chrome 打开微博搜索，抓帖子图 → 小图换大图 → 发微信
# @desc 下载微博图（打开微博搜索，抓九宫格图并小图换大图，存到 ~ 报张数）
# @usage tools/weibo_imgs.sh <明星/关键词> [页数 | A-B | all，默认 all] [--save 目录] [--each] [--limit N] [--to 会话]
# @rule **下载微博图**：说“下载微博图 <明星> / 抓 <明星> 的微博图 / 找 <明星> 的图”→ `tools/weibo_imgs.sh <明星>`。默认**自动翻页直到没有新图**（也可 `N` 或 `A-B` 限页）。用**已登录的 Chrome** 打开 `s.weibo.com` 搜索，抓帖子九宫格里的图并自动把小图换成大图，**保存到 ~ 下的目录**并报告下载张数（默认不发微信）。只有用户明确说“发我微信/发过来”才加 `--to` 发送。
# @order 20
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"

TO=""; EACH=""; KW=""; PSTART=1; PEND=0; LIMIT=""; SAVE=""   # PEND=0 表示自动翻到没有新图
while [ $# -gt 0 ]; do
    case "$1" in
        --to)    TO="${2:-}"; shift 2 ;;
        --save)  SAVE="${2:-}"; shift 2 ;;
        --each)  EACH="--each"; shift ;;
        --limit) LIMIT="${2:-}"; shift 2 ;;
        all|全部) PEND=0; shift ;;
        [0-9]*-[0-9]*) PSTART="${1%-*}"; PEND="${1#*-}"; shift ;;
        [0-9]*)  PEND="$1"; shift ;;
        *)       [ -z "$KW" ] && KW="$1"; shift ;;
    esac
done
[ -z "$KW" ] && { echo "用法: weibo_imgs.sh <明星/关键词> [页数或 A-B] [--save 目录] [--each] [--limit N] [--to 会话]" >&2; exit 2; }
command -v node >/dev/null || { echo "需要 node" >&2; exit 3; }
command -v jq >/dev/null || { echo "需要 jq" >&2; exit 3; }

enc="$(printf '%s' "$KW" | jq -sRr @uri)"
TMPURL="/tmp/wb_imgs_urls_$$.txt"; : > "$TMPURL"
MAXPAGE="${WEIBO_MAX_PAGE:-40}"

fetch_page() { # $1=页码；追加去重；设置全局 ADDNEW
    local before after
    before="$(grep -c . "$TMPURL" || true)"
    node "$DIR/weibo_fetch.js" "https://s.weibo.com/weibo?q=$enc&page=$1" 2>/dev/null >> "$TMPURL"
    sort -u "$TMPURL" | grep -E 'sinaimg' > "$TMPURL.u" && mv "$TMPURL.u" "$TMPURL"
    after="$(grep -c . "$TMPURL" || true)"
    ADDNEW=$((after - before))
}

RANGE=""
if [ "$PEND" -eq 0 ]; then
    p="$PSTART"; empty=0; last="$PSTART"
    while [ "$p" -le "$MAXPAGE" ]; do
        echo "  · 抓第 $p 页..." >&2
        fetch_page "$p"; last="$p"
        if [ "$ADDNEW" -le 0 ]; then empty=$((empty + 1)); else empty=0; fi
        [ "$empty" -ge 2 ] && break        # 连续两页没新图 → 到头了
        p=$((p + 1))
    done
    RANGE="$PSTART..$last"
else
    for p in $(seq "$PSTART" "$PEND"); do
        echo "  · 抓第 $p 页..." >&2
        fetch_page "$p"
    done
    RANGE="$PSTART..$PEND"
fi

n="$(grep -c . "$TMPURL" || true)"
echo "抓到 $n 张图 URL（页 $RANGE）"
[ "${n:-0}" -eq 0 ] && { echo "没抓到图（检查 Chrome 是否登录、是否开着调试口 9222）" >&2; rm -f "$TMPURL"; exit 1; }

args=(); [ -n "$EACH" ] && args+=(--each); [ -n "$LIMIT" ] && args+=(--limit "$LIMIT")
if [ -n "$TO" ]; then
    "$DIR/send_images.sh" --to "$TO" "${args[@]}" < "$TMPURL"
else
    OUTDIR="${SAVE:-$HOME/微博图/${KW}_$(date +%Y%m%d_%H%M%S)}"
    "$DIR/send_images.sh" --save "$OUTDIR" "${args[@]}" < "$TMPURL"
fi
rm -f "$TMPURL"
