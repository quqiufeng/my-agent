#!/usr/bin/env bash
# tools/weibo_hot.sh — 微博热搜 → Kami 排版图 + 文字，发微信（AI 助手用）
# @desc 抓微博实时热搜榜，生成排版图并（可选）发文字到微信（默认文件传输助手）
# @usage tools/weibo_hot.sh [--to 会话] [--limit N（默认15）] [--display] [--no-send]
# @rule 用户说“微博热 / 微博热搜 / 微博热搜榜” → `tools/weibo_hot.sh`（默认出图+发微信）；要**只要文本**加 `--display`。
# @order 22
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT="/opt/my-agent/operator/report"
TO="文件传输助手"; LIMIT=15; DISP=0; SEND=1
while [ $# -gt 0 ]; do
  case "$1" in
    --to) TO="${2:-文件传输助手}"; shift 2 ;;
    --limit) LIMIT="${2:-30}"; shift 2 ;;
    --display) DISP=1; SEND=0; shift ;;
    --no-send) SEND=0; shift ;;
    *) shift ;;
  esac
done
command -v jq >/dev/null || { echo "需要 jq" >&2; exit 3; }

CK="$(printf '%s' "${WEIBO_COOKIE:-}")"; [ -z "$CK" ] && CK="$(sed -n 's/^WEIBO_COOKIE=//p' "$HOME/.env" 2>/dev/null | head -1 | sed "s/^'//; s/'\$//")"
[ -z "$CK" ] && CK="$(cat "$HOME/.myagent_weibo_cookie" 2>/dev/null)"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124 Safari/537.36"
STAMP="$(date +%Y%m%d_%H%M%S)"; OUT="/tmp/myagent_weibohot_${STAMP}"

curl -s --max-time 20 -A "$UA" -H "Referer: https://weibo.com/" ${CK:+-b "$CK"} "https://weibo.com/ajax/side/hotSearch" -o "$OUT.json"
jq -r '.data.realtime[] | [.rank, .word, .num] | @tsv' "$OUT.json" 2>/dev/null | head -n "$LIMIT" | awk -F'\t' '{printf "%d\t%s\t%s\n", NR, $2, $3}' > "$OUT.tsv"
n="$(grep -c . "$OUT.tsv" || true)"
[ "${n:-0}" -gt 0 ] || { echo "未取到热搜（cookie 失效？）" >&2; exit 1; }

luajit "$REPORT/weibo_hot.lua" "$OUT.html" "$OUT.txt" "$OUT.tsv"

if [ "$DISP" = 1 ]; then cat "$OUT.txt"; exit 0; fi
cat "$OUT.txt"

# 出图
"$REPORT/render.sh" "$OUT.html" "$OUT.png" 820 >/dev/null 2>&1
echo "图片: $OUT.png"

if [ "$SEND" = 1 ]; then
  [ -s "$OUT.png" ] && { "$DIR/wechat_send_file.sh" "$OUT.png" --to "$TO" >/dev/null 2>&1 && echo "已发图 → $TO"; sleep 3; }
  "$DIR/wechat_send.sh" --to "$TO" "$(cat "$OUT.txt")" >/dev/null 2>&1 && echo "已发文字 → $TO"
fi
