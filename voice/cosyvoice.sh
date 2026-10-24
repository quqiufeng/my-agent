#!/usr/bin/env bash
# voice/cosyvoice.sh — 克隆音色管理 + 指定音色发声（LuaJIT 实现）
# 用法: cosyvoice.sh list | add <名> <参考.wav> ["参考文本"] | synth <名> "文本" <out.wav> [语速] | speak <名> "文本" [语速] | del <名>
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/cosyvoice.lua" "$@"
