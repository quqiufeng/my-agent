#!/usr/bin/env bash
# tools/weibo_imgs.sh — 看某明星微博图：用已登录 Chrome 打开微博搜索，抓帖子图 → 小图换大图 → 发微信
# @desc 下载微博图（打开微博搜索，抓九宫格图并小图换大图，存到 ~ 报张数）
# @usage tools/weibo_imgs.sh <明星/关键词> [页数 | A-B | all，默认 20] [--save 目录] [--each] [--limit N] [--to 会话] [--refresh-cookie]
# @rule **下载微博图**：说“下载微博图 <明星> / 抓 <明星> 的微博图 / 找 <明星> 的图”→ `tools/weibo_imgs.sh <明星>`。**默认抓 1..20 页**（也可 `N`、`A-B` 或 `all`）。用**微博 cookie（存在 ~/.env，长期免授权）** curl 抓 `s.weibo.com` 搜索页，解析帖子图片并自动把小图换成大图，**保存到 ~ 下的目录**并报告下载张数（默认不发微信）。只有用户明确说“发我微信/发过来”才加 `--to` 发送；cookie 过期（抓不到）时才用 `--refresh-cookie` 从已登录 Chrome 重取一次。
# @order 20
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"

TO=""; EACH=""; KW=""; PSTART=1; PEND=20; LIMIT=""; SAVE=""; FORCE_REFRESH=0   # 默认抓 1..20 页；PEND=0 表示自动翻到没有新图
while [ $# -gt 0 ]; do
    case "$1" in
        --refresh-cookie) FORCE_REFRESH=1; shift ;;
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
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
# cookie 缓存：只从 Chrome(CDP) 取一次，之后纯 curl 爬，不再碰浏览器/不弹授权
CKFILE="${WEIBO_COOKIE_FILE:-$HOME/.myagent_weibo_cookie}"
env_get() { sed -n 's/^WEIBO_COOKIE=//p' "$HOME/.env" 2>/dev/null | head -1 | sed "s/^'//; s/'\$//"; }
ck_refresh() {   # 从 Chrome(CDP) 取一次并写缓存 + ~/.env（长期复用）
    CK="$(node "$DIR/weibo_cookies.js" 2>/dev/null)"
    [ -n "$CK" ] || return
    printf '%s' "$CK" > "$CKFILE"
    if grep -q '^WEIBO_COOKIE=' "$HOME/.env" 2>/dev/null; then
        grep -v '^WEIBO_COOKIE=' "$HOME/.env" > "$HOME/.env.tmp" && mv "$HOME/.env.tmp" "$HOME/.env"
    fi
    printf "WEIBO_COOKIE='%s'\n" "$CK" >> "$HOME/.env"
}
CK="${WEIBO_COOKIE:-}"; [ -z "$CK" ] && CK="$(env_get)"
[ -z "$CK" ] && CK="$(cat "$CKFILE" 2>/dev/null)"
# 只在「显式 --refresh-cookie」或「根本没有 cookie」时才找 Chrome(CDP) 取一次；之后纯 curl
if [ "$FORCE_REFRESH" = "1" ] || [ -z "$CK" ]; then
    command -v node >/dev/null || { echo "需要 node 才能取 cookie" >&2; exit 3; }
    ck_refresh
fi
[ -z "$CK" ] && { echo "没有微博 cookie。运行一次: weibo_imgs.sh --refresh-cookie（需已登录 Chrome）" >&2; exit 3; }

curl_page() { curl -s --max-time 25 -A "$UA" -H "Referer: https://s.weibo.com/" -b "$CK" "$1" 2>/dev/null; }

fetch_page() { # $1=页码；纯 curl 抓 HTML → 解析 pic_ids → 大图 URL；设置全局 ADDNEW
    local before after html url
    before="$(grep -c . "$TMPURL" || true)"
    url="https://s.weibo.com/weibo?q=$enc&page=$1"
    html="$(curl_page "$url")"
    printf '%s' "$html" | grep -oE 'pic_ids=[^"&<]*' | sed 's/pic_ids=//' | tr ',' '\n' \
        | while IFS= read -r id; do [ -n "$id" ] && printf 'https://wx1.sinaimg.cn/large/%s.jpg\n' "$id"; done >> "$TMPURL"
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
    export SAVE_PREFIX="$(date +%m%d_%H%M%S)_"          # 一个明星一个目录，文件名带运行时间
    OUTDIR="${SAVE:-$HOME/微博图/${KW}}"
    "$DIR/send_images.sh" --save "$OUTDIR" "${args[@]}" < "$TMPURL"
fi
rm -f "$TMPURL"
