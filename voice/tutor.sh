#!/usr/bin/env bash
# voice/tutor.sh — 英语口语陪练入口（LuaJIT 编排 + C++ 内核）
# 用法: tutor.sh [--once] [--no-forward]
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/tutor.lua" "$@"
