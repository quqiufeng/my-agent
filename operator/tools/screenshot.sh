#!/usr/bin/env bash
# tools/screenshot.sh — 截屏（默认全屏），返回图片路径（LuaJIT 实现）
# @rule **截屏**：说“截个屏/截屏发我”→ `screenshot.sh`（返回路径），再用 `wechat_send_file.sh <路径> [--to 来源会话]` 发回。
# @order 6
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/screenshot.lua" "$@"
