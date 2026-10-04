#!/usr/bin/env bash
# wechat-ocr/once.sh — 单次流程：send "文本" | recv | peek
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

export LD_LIBRARY_PATH="${DIR}/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:${LD_LIBRARY_PATH:-}"
export LUA_PATH="${DIR}/?.lua;${DIR}/lua/?.lua;${DIR}/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="${DIR}/lib/?.so;/usr/local/lualib/?.so;;"
export DISPLAY="${DISPLAY:-:0}"
export AGENT_URL="${AGENT_URL:-http://localhost:4097}"
export OPERATOR_DIR="${OPERATOR_DIR:-/opt/my-agent/operator}"

exec luajit "${DIR}/once.lua" "$@"
