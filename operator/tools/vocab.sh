#!/usr/bin/env bash
# tools/vocab.sh — 记单词：屏幕弹英文单词，读对进下一个，读错弹释义卡（LuaJIT 实现）
# @desc 记单词（弹卡片→读单词判发音→✓下一个 / ✗弹释义卡帮助记忆，LuaJIT 实现）
# @usage tools/vocab.sh start|stop|status | add <英文> <中文> | list
# @rule **记单词**：说“记单词 / 背单词 / 开始背单词”→ `tools/vocab.sh start`；“停了/结束背单词”→ `stop`；要加词 → `add <英文> <中文>`。开始后弹卡片，你读单词：**读对进下一个；读错弹带中文翻译的卡片帮助记忆**。
# @order 15
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"
exec luajit "$DIR/vocab.lua" "$@"
