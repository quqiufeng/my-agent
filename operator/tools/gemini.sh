#!/usr/bin/env bash
# tools/gemini.sh — 问 Google AI(Gemini) → 默认出图+发微信（LuaJIT 实现）
# @desc 用 Chrome(CDP) 问 Google AI(Gemini)；默认排版图+文字发微信，--display 仅打印回答
# @usage tools/gemini.sh <问题> [--display] [--to 会话] [--no-image] [--no-send]
# @rule 用户说“问 Google AI / 问 Gemini / 让 AI 回答 <问题> 并发我微信” → `tools/gemini.sh "<问题>"`；要**只要文本**供程序用 → 加 `--display`。
# @order 28
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"
exec luajit "$DIR/gemini.lua" "$@"
