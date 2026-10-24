#!/usr/bin/env bash
# tools/browser.sh — 操作本机 Chrome（不新开浏览器，LuaJIT 实现）
# 用法: browser.sh new_tab
#       browser.sh open <url>
#       browser.sh search <关键词>
#       browser.sh ai_search <问题>
#       browser.sh screenshot [输出路径]
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="/opt/my-agent/wechat-ocr/lib:${LD_LIBRARY_PATH:-}"
export LUA_PATH="/opt/my-agent/wechat-ocr/lua/?.lua;/opt/my-agent/wechat-ocr/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;"
export DISPLAY="${DISPLAY:-:0}"
exec luajit "$DIR/browser.lua" "$@"
