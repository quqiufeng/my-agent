#!/usr/bin/env bash
# @desc 监督 opencode 工作：向指定 opencode TUI 标签页发送“继续”并回车，避免任务中断（LuaJIT 实现）
# @usage tools/opencode_supervise.sh [要发送的文字，默认“继续”]
# @rule 说“监督 opencode/让 opencode 继续/盯着它干活”→ tools/opencode_supervise.sh；默认发送“继续”，可带自定义文字。
# @order 52
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec env LUA_PATH="$DIR/?.lua;;" luajit "$DIR/opencode_supervise.lua" "$@"
