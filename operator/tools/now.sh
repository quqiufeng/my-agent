#!/usr/bin/env bash
# tools/now.sh — 返回当前日期与时间（LuaJIT 实现）
# @rule **问时间/日期**（“现在几点 / 今天几号 / 星期几”）→ 用 `now.sh`，不要为此调浏览器或其它工具。
# @order 5
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/now.lua" "$@"
