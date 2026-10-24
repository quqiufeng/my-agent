#!/usr/bin/env bash
# voice/listen.sh — 启动语音入口（麦克风常驻监听，LuaJIT 编排 + C++ 内核）
# 用法: listen.sh [--once] [--no-forward] [--file <wav>]
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/listen.lua" "$@"
