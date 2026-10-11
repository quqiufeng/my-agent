#!/usr/bin/env bash
# tools/git_trending.sh — GitHub 每日热门：查信息 → 出 Kami 图 → 发微信
# @desc GitHub 今日热门：抓取 Trending → 生成排版图 → 发微信（默认文件传输助手）
# @usage tools/git_trending.sh [--since daily|weekly|monthly] [--lang <lang>] [--limit N] [--to 联系人] [--text] [--show] [--no-send]
# @rule 用户说“今日github热门 / GitHub 今日热门 / 最近什么项目火” → 用 `tools/git_trending.sh`（默认出图并发微信）；不要动用浏览器。
# @order 30
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT="/opt/my-agent/operator/report"

since=daily; lang=""; limit=15; to="文件传输助手"; text_only=0; show=0; send=1
while [ $# -gt 0 ]; do
  case "$1" in
    --since) since="${2:-daily}"; shift 2 ;;
    --lang)  lang="${2:-}";      shift 2 ;;
    --limit) limit="${2:-15}";   shift 2 ;;
    --to)    to="${2:-}";        shift 2 ;;
    --text)  text_only=1;        shift ;;
    --show)  show=1;             shift ;;
    --no-send) send=0;           shift ;;
    *) shift ;;
  esac
done

STAMP="$(date +%Y%m%d_%H%M%S)"
HTML="/tmp/myagent_gittrend_${STAMP}.html"
PNG="/tmp/myagent_gittrend_${STAMP}.png"

# 1) 文本简报（同时打印给大脑日志）
echo "== GitHub ${since} 热门 =="
if [ "$text_only" = "1" ]; then
  luajit -e '
package.path="/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;"..package.path
local ak=require("agentkit"); local gh=ak.app("github")
for _,l in ipairs(gh.brief({since="'"$since"'", lang="'"$lang"'", limit=tonumber("'"$limit"'")})) do print(l) end
'
  exit 0
fi

# 2) 生成 Kami HTML
luajit "$REPORT/github_trending.lua" "$HTML" "$since" "$lang" "$limit" || { echo "生成 HTML 失败" >&2; exit 1; }

# 3) 渲染 PNG
"$REPORT/render.sh" "$HTML" "$PNG" 820 >/dev/null || { echo "渲染失败" >&2; exit 1; }
echo "图片: $PNG"

# 4) 打开查看（可选）
[ "$show" = "1" ] && command -v xdg-open >/dev/null && xdg-open "$PNG" >/dev/null 2>&1 &

# 5) 发微信（图片）
if [ "$send" = "1" ]; then
  "$DIR/wechat_send_file.sh" "$PNG" --to "$to" && echo "已发微信 → $to"
fi
