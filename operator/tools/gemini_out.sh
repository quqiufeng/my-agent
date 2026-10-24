#!/usr/bin/env bash
# tools/gemini_out.sh — 把（Gemini 等）获取到的结果按目标转发（LuaJIT 实现）
# 用法:
#   gemini_out.sh <wechat|opencode> "文本"
#   echo "多行文本" | gemini_out.sh <wechat|opencode>
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/gemini_out.lua" "$@"
