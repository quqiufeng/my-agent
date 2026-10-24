#!/usr/bin/env bash
# tools/english.sh — 英语口语陪练：开/关麦克风陪练（背景跑 voice/voice.sh tutor，LuaJIT 实现）
# @desc 英语口语陪练（麦克风识别英文，回复用英文音色朗读）
# @usage tools/english.sh start|stop|status
# @rule **英语口语陪练**：收到 `[英语口语] ...` 时，你是英语口语陪练——用**英文**简短回应（1-3 句）、温和指出更自然的说法，并反问一句让对话继续；回复一律 `tools/say.sh "英文"` 读出（陪练模式会自动用英文音色）。用户说中文或要翻译时，再中英对照。
# @order 14
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/english.lua" "$@"
