#!/usr/bin/env bash
# voice/say.sh — 文本转语音 → USB 音响（LuaJIT 实现）
# 用法: say.sh [--voice <音色名>] "要说的文本"
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/say.lua" "$@"
