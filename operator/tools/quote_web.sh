#!/usr/bin/env bash
# tools/quote_web.sh — 看行情：浏览器打开搜狐行情页（个股/指数），全屏截图发微信（LuaJIT 实现）
# @desc 看行情（浏览器打开搜狐行情页并全屏截图发微信）
# @usage tools/quote_web.sh [名称或代码] [--to 会话]
# @rule **看行情/看盘/大盘**：说“看下<股票>行情 / 大盘怎么样 / 看盘 / 行情截图”→ `tools/quote_web.sh [名称或代码]`（不传=上证指数）。它会用浏览器打开搜狐行情页并全屏截图发来源会话。
# @order 18
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"
exec luajit "$DIR/quote_web.lua" "$@"
