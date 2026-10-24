#!/usr/bin/env bash
# tools/progress.sh — 查看开发进度：逐个 tab 截图 opencode，合并后发微信（LuaJIT 实现）
# @rule **看开发进度**：说“看看开发进度 / 项目进度 / 各项目怎么样 / 进度”→ `progress.sh`（点击 qterminal，逐个 tab 截图 opencode，合并后发来源会话）。
# @order 13
# 用法: progress.sh [--to 会话]
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"
exec luajit "$DIR/progress.lua" "$@"
