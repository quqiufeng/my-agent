#!/usr/bin/env bash
# tools/weibo_album.sh — 微博「相册」大图下载：按昵称搜出 uid → 相册接口翻页 → 存 ~ 报张数
# 原理：s.weibo.com/user?q=<昵称> 解析 uid；再 curl /ajax/profile/getImageWall（游标 since_id 翻页）；
#       大图 = https://wx1.sinaimg.cn/large/<pid>.jpg。比搜索页快、且直接给原图。
# @desc 微博相册大图下载（搜昵称定 uid → 相册接口翻页取大图 → 存 ~ 报张数）
# @usage tools/weibo_album.sh <昵称|uid> [页数 | all，默认 20] [--save 目录] [--to 会话] [--limit N]
# @rule **下载某人的微博相册（全量大图）**：说“下载 <某人> 的微博相册 / 抓 <某人> 相册的图 / <某人> 相册”→ `tools/weibo_album.sh <昵称>`。先按昵称搜出 uid（也可直接给数字 uid），再用相册接口翻页取**大图**（比搜索页快很多），存到 ~ 下的目录并报张数（默认不发微信；说“发我”才加 `--to`）。
# @order 21
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"

TO=""; SAVE=""; LIMIT=""; KW=""; PAGES=20
while [ $# -gt 0 ]; do
    case "$1" in
        --to)    TO="${2:-}"; shift 2 ;;
        --save)  SAVE="${2:-}"; shift 2 ;;
        --limit) LIMIT="${2:-}"; shift 2 ;;
        --refresh-cookie) REFRESH=1; shift ;;
        all|全部) PAGES=0; shift ;;
        [0-9]*)  PAGES="$1"; shift ;;
        *)       [ -z "$KW" ] && KW="$1"; shift ;;
    esac
done
[ -z "$KW" ] && { echo "用法: weibo_album.sh <昵称|uid> [页数|all，默认20] [--save 目录] [--to 会话]" >&2; exit 2; }
command -v jq >/dev/null || { echo "需要 jq" >&2; exit 3; }

UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
CKFILE="${WEIBO_COOKIE_FILE:-$HOME/.myagent_weibo_cookie}"
env_get() { sed -n 's/^WEIBO_COOKIE=//p' "$HOME/.env" 2>/dev/null | head -1 | sed "s/^'//; s/'\$//"; }
CK="${WEIBO_COOKIE:-}"; [ -z "$CK" ] && CK="$(env_get)"; [ -z "$CK" ] && CK="$(cat "$CKFILE" 2>/dev/null)"
[ -z "$CK" ] && { echo "没有微博 cookie。先跑: weibo_imgs.sh --refresh-cookie（需已登录 Chrome）" >&2; exit 3; }

get() { curl -s --max-time 25 -A "$UA" -H "Referer: $1" -b "$CK" "$2" 2>/dev/null; }

# ── 1) 解析 uid ─────────────────────────────────────────────
if printf '%s' "$KW" | grep -qE '^[0-9]+$'; then
    WUID="$KW"; NAME=""
else
    enc="$(printf '%s' "$KW" | jq -sRr @uri)"
    # 综合搜索页第一条（通常是官方个人主页）
    html="$(get "https://s.weibo.com/" "https://s.weibo.com/weibo?q=$enc")"
    matches="$(printf '%s' "$html" | grep -oE 'href="//weibo.com/u/[0-9]+" class="name"[^>]*>[^<]*' \
        | sed -E 's#.*u/([0-9]+)".*>(.*)#\1\t\2#' | awk '!seen[$1]++')"
    [ -z "$matches" ] && { echo "没搜到用户「$KW」（cookie 失效？试 --refresh-cookie）" >&2; exit 1; }
    # 前 5 条里优先精确同名，否则取第一条
    exact="$(printf '%s' "$matches" | head -5 | awk -F'\t' -v n="$KW" '$2==n{print $1; exit}')"
    WUID="${exact:-$(printf '%s' "$matches" | head -1 | cut -f1)}"
    NAME="$(printf '%s' "$matches" | awk -F'\t' -v u="$WUID" '$1==u{print $2; exit}')"
fi

# 用 profile 接口核对昵称（更权威），拿不到就用搜索结果名
info="$(get "https://weibo.com/u/$WUID" "https://weibo.com/ajax/profile/info?uid=$WUID")"
sn="$(printf '%s' "$info" | jq -r '.data.user.screen_name // empty' 2>/dev/null)"
[ -n "$sn" ] && NAME="$sn"
[ -z "$NAME" ] && NAME="$KW"
echo "目标：$NAME （uid=$WUID）"

# ── 2) 翻页取相册 pid ───────────────────────────────────────
TMPURL="/tmp/wb_album_urls_$$.txt"; : > "$TMPURL"
since="0"; page=0
while :; do
    page=$((page+1))
    [ "$PAGES" -gt 0 ] && [ "$page" -gt "$PAGES" ] && break
    resp="$(get "https://weibo.com/u/$WUID" "https://weibo.com/ajax/profile/getImageWall?uid=$WUID&sinceid=$since")"
    n="$(printf '%s' "$resp" | jq -r '.data.list | length' 2>/dev/null)"
    if ! [ "${n:-0}" -gt 0 ] 2>/dev/null; then
        if [ "$page" -eq 1 ]; then echo "相册为空或接口异常（cookie 失效？）" >&2; fi
        break
    fi
    printf '%s' "$resp" | jq -r '.data.list[] | select(.type=="pic") | .pid' \
        | while IFS= read -r pid; do [ -n "$pid" ] && printf 'https://wx1.sinaimg.cn/large/%s.jpg\n' "$pid"; done >> "$TMPURL"
    since="$(printf '%s' "$resp" | jq -r '.data.since_id')"
    echo "  · 第 $page 页 +$n（累计 $(sort -u "$TMPURL" | grep -c .)）" >&2
    [ -n "$since" ] && [ "$since" != "null" ] || break
done
sort -u "$TMPURL" -o "$TMPURL"
total="$(grep -c . "$TMPURL" || true)"
echo "相册共 $total 张大图（页 1..$page）"
[ "${total:-0}" -eq 0 ] && { rm -f "$TMPURL"; exit 1; }

# ── 3) 下载（复用 send_images.sh：换大图/尺寸回退/保存/报张数）──
args=(); [ -n "$LIMIT" ] && args+=(--limit "$LIMIT")
if [ -n "$TO" ]; then
    "$DIR/send_images.sh" --to "$TO" "${args[@]}" < "$TMPURL"
else
    export SAVE_PREFIX="$(date +%m%d_%H%M%S)_"
    OUTDIR="${SAVE:-$HOME/微博图/${NAME}}"
    "$DIR/send_images.sh" --save "$OUTDIR" "${args[@]}" < "$TMPURL"
fi
rm -f "$TMPURL"
