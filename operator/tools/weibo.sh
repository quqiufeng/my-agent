#!/usr/bin/env bash
# tools/weibo.sh — 打开微博搜索指定明星/关键词，全屏截图发微信
# @desc 微博搜索（浏览器打开微博搜索页并全屏截图发微信）
# @usage tools/weibo.sh <关键词> [--to 会话]
# @rule **打开微博搜索页(截图)**：说“打开微博 / 微博搜 <关键词>，要网页截图”→ `tools/weibo.sh <关键词>`（打开搜索页并全屏截图）。**要找/发某明星的图片** → 用 `weibo_imgs.sh`。
# @order 19
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"

TO=""; KW=""
while [ $# -gt 0 ]; do
    case "$1" in
        --to) TO="${2:-}"; shift 2 ;;
        *) [ -z "$KW" ] && KW="$1"; shift ;;
    esac
done
[ -z "$KW" ] && { echo "用法: weibo.sh <关键词> [--to 会话]" >&2; exit 2; }
command -v jq >/dev/null || { echo "需要 jq" >&2; exit 3; }

enc="$(printf '%s' "$KW" | jq -sRr @uri)"
URL="https://s.weibo.com/weibo?q=$enc"
echo "打开: $URL"

# 在现有 Chrome 里打开（已有实例会新开标签）
setsid google-chrome "$URL" >/dev/null 2>&1 &
sleep 8
cid="$(xdotool search --name 'Google Chrome' 2>/dev/null | head -1)"
[ -n "$cid" ] && xdotool windowactivate --sync "$cid"
sleep 3

OUT="/tmp/myagent_weibo_$(date +%Y%m%d_%H%M%S).png"
import -window root "$OUT" 2>/dev/null
[ -s "$OUT" ] || { echo "截图失败" >&2; exit 1; }
echo "截图: $OUT"

if [ -n "$TO" ]; then "$DIR/wechat_send_file.sh" "$OUT" --to "$TO"; echo "已发到微信「$TO」"
else "$DIR/wechat_send_file.sh" "$OUT"; echo "已发到微信文件传输助手"; fi
