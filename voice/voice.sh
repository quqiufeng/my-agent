#!/usr/bin/env bash
# voice/voice.sh — 语音模块统一入口（LuaJIT 实现）
# 用法: voice.sh say "文本" | listen | tutor | once | test | camera | app | orb
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/voice.lua" "$@"
