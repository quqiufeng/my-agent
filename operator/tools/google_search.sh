#!/usr/bin/env bash
# tools/google_search.sh — 谷歌搜索/新闻 → Kami 排版图 + 文字，发微信（LuaJIT 实现）
# @desc 用 Chrome(CDP/DOM) 谷歌搜索，先生成排版图再发文字到微信（默认文件传输助手）
# @usage tools/google_search.sh <关键词> [--news] [--to 会话] [--no-image] [--no-send]
# @rule 用户说“帮我 google 搜索/查一下 <关键词> 并发我微信” → `tools/google_search.sh "<关键词>"`（默认发图+文字）；查新闻加 `--news`。
# @order 29
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"
exec luajit "$DIR/google_search.lua" "$@"
