#!/usr/bin/env bash
# tools/chrome_debug.sh — 启动「固定调试端口」的 Chrome（LuaJIT 实现）
# @desc 每次启动前同步 profile，再用固定调试端口起专用 Chrome，供 chrome-devtools MCP(--browser-url) 连接（免反复授权）
# @usage tools/chrome_debug.sh [端口]        # 默认 9222
# @rule 需要 Chrome 供 MCP 使用时 → 先 `tools/chrome_debug.sh`（固定端口实例，免弹授权）；不要用系统默认 Chrome 直连。
# @order 16
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/chrome_debug.lua" "$@"
