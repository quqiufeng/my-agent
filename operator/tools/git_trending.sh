#!/usr/bin/env bash
# tools/git_trending.sh — GitHub 每日热门仓库（Trending）
# @desc 获取 GitHub Trending 仓库（今日/本周/每月，可按语言），可 --save 记录当天快照
# @usage tools/git_trending.sh [--since daily|weekly|monthly] [--lang <lang>] [--limit N] [--save]
# @rule 问“GitHub 热门/趋势/今日热门项目/最近什么项目火” → 用 `git_trending.sh`（可加 `--lang`/`--since`/`--save`）；不要动用浏览器。
# @order 30
set -uo pipefail
since=daily; lang=""; limit=15; save=0
while [ $# -gt 0 ]; do
  case "$1" in
    --since) since="${2:-daily}"; shift 2 ;;
    --lang)  lang="${2:-}";      shift 2 ;;
    --limit) limit="${2:-15}";   shift 2 ;;
    --save)  save=1;             shift ;;
    *) shift ;;
  esac
done
luajit -e '
package.path="/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;"..package.path
local ak=require("agentkit"); local gh=ak.app("github")
local opts={since="'"$since"'", lang="'"$lang"'", limit=tonumber("'"$limit"'")}
for _,l in ipairs(gh.brief(opts)) do print(l) end
if "'"$save"'"=="1" then
  local f,n=gh.save_daily(opts); io.stderr:write(string.format("已记录 %d 条 → %s\n", n, f))
end
'
