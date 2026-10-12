#!/usr/bin/env bash
# tools/google_search.sh — 谷歌搜索并把结果发微信（AI 助手用）
# @desc 用 Chrome(CDP/DOM) 谷歌搜索关键词，整理结果发到微信（默认文件传输助手）
# @usage tools/google_search.sh <关键词> [--news] [--to 会话] [--limit N] [--image] [--no-send]
# @rule 用户说“帮我 google 搜索/查一下 <关键词> 并发我微信” → `tools/google_search.sh "<关键词>"`；查新闻加 `--news`。
# @order 29
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

KW=""; NEWS=0; TO="文件传输助手"; LIMIT=10; IMG=0; SEND=1
while [ $# -gt 0 ]; do
  case "$1" in
    --news) NEWS=1; shift ;;
    --to) TO="${2:-文件传输助手}"; shift 2 ;;
    --limit) LIMIT="${2:-10}"; shift 2 ;;
    --image) IMG=1; shift ;;
    --no-send) SEND=0; shift ;;
    *) [ -z "$KW" ] && KW="$1"; shift ;;
  esac
done
[ -n "$KW" ] || { echo "用法: google_search.sh <关键词> [--news] [--to 会话]" >&2; exit 2; }

# 图形会话环境
if [ -z "${XAUTHORITY:-}" ] && [ -z "${DISPLAY:-}" ]; then
  P=$(pgrep -x pcmanfm-qt | head -1)
  [ -n "$P" ] && XAUTHORITY=$(tr '\0' '\n' < "/proc/$P/environ" 2>/dev/null | sed -n 's/^XAUTHORITY=//p')
fi
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-}"

# 1) 确保专用 Chrome 实例在跑
ss -ltn 2>/dev/null | grep -q ':9222 ' || "$DIR/chrome_debug.sh" >/dev/null 2>&1

# 2) 取结果（走 CDP/DOM）
export AK_KW="$KW" AK_MODE="$([ "$NEWS" = 1 ] && echo news || echo search)" AK_LIMIT="$LIMIT"
TXT=$(luajit -e '
package.path="/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;"..package.path
local ak=require("agentkit"); local g=ak.app("google")
local kw=os.getenv("AK_KW"); local mode=os.getenv("AK_MODE"); local lim=tonumber(os.getenv("AK_LIMIT")) or 10
if mode=="news" then g.news(kw) else g.search(kw) end
os.execute("sleep 3")
local out={}
if mode=="news" then
  out[#out+1]="【谷歌新闻："..kw.."】"
  for i,r in ipairs(g.news_results(lim)) do
    out[#out+1]=string.format("%d. %s（%s）\n%s", i, r.title, r.source, r.snippet)
  end
else
  out[#out+1]="【谷歌搜索："..kw.."】"
  for i,r in ipairs(g.results(lim)) do
    out[#out+1]=string.format("%d. %s — %s\n%s", i, r.title,
      (r.cite~="" and r.cite or r.url_real), r.snippet)
  end
  local pn=g.panel(); if pn~="" then out[#out+1]="◆ 百科："..pn:gsub("\n"," "):sub(1,300) end
end
io.write(table.concat(out,"\n"))
' 2>/dev/null)

[ -n "$TXT" ] || { echo "未取到结果" >&2; exit 1; }
echo "$TXT"

# 3) 发送
if [ "$SEND" = 1 ]; then
  "$DIR/wechat_send.sh" --to "$TO" "$TXT" >/dev/null 2>&1 && echo "已发微信 → $TO"
fi
