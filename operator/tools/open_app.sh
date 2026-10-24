#!/usr/bin/env bash
# tools/open_app.sh — 打开白名单内的本机应用（LuaJIT 实现）
# 用法: open_app.sh <chrome|terminal|files|editor|wechat>
set -uo pipefail
export DISPLAY="${DISPLAY:-:0}"
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/open_app.lua" "$@"
