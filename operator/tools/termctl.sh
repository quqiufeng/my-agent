#!/usr/bin/env bash
# tools/termctl.sh — 控制 qterminal 里的命令行任务（LuaJIT 实现）
# @desc 控制 qterminal 中的命令行应用：列出标签数 / 截图发微信 / 向指定标签注入指令并回车执行
# @usage tools/termctl.sh tabs | shot [N] [--to 会话] | send <N> "<指令>" [--no-enter]
# @rule 说“命令行/终端有几个任务(标签)”→ 只调 `tools/termctl.sh tabs`，把它输出的 **任务数** 直接回复给用户（不用解释）。
# @rule 说“截图 tabN 的进度/把这个任务进度发我”→ `tools/termctl.sh shot N`；默认发文件传输助手，指定会话用 `shot N --to <会话>`。
# @rule 要控制某个标签里的 opencode/命令行执行一条指令 → `tools/termctl.sh send <N> "<指令>"`（会注入输入框并回车执行）。
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"
exec luajit "$DIR/termctl.lua" "$@"
