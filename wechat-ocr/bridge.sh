#!/usr/bin/env bash
# wechat-ocr/bridge.sh — 启动微信入口桥（监控 → [微信输入] → 大脑）
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

export LD_LIBRARY_PATH="${DIR}/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:${LD_LIBRARY_PATH:-}"
export LUA_PATH="${DIR}/lua/?.lua;${DIR}/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="${DIR}/lib/?.so;/usr/local/lualib/?.so;;"
export DISPLAY="${DISPLAY:-:0}"
export AGENT_URL="${AGENT_URL:-http://localhost:4097}"
export WECHAT_POLL_SEC="${WECHAT_POLL_SEC:-10}"
export WECHAT_SENT_LOG="${WECHAT_SENT_LOG:-/tmp/myagent_wechat_sent.log}"

exec luajit "${DIR}/bridge.lua"
