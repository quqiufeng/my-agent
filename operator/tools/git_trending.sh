#!/usr/bin/env bash
# tools/git_trending.sh — GitHub 每日热门：查信息 → 出 Kami 图 → 发微信（LuaJIT 实现）
# @desc GitHub 今日热门：抓取 Trending → 生成排版图 → 发微信（默认文件传输助手）
# @usage tools/git_trending.sh [--since daily|weekly|monthly] [--lang <lang>] [--limit N] [--to 联系人] [--text] [--show] [--no-send]
# @rule 用户说“今日github热门 / GitHub 今日热门 / 最近什么项目火” → 用 `tools/git_trending.sh`（默认出图并发微信）；不要动用浏览器。
# @order 30
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/git_trending.lua" "$@"
