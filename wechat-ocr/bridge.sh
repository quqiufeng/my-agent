#!/usr/bin/env bash
# wechat-ocr/bridge.sh — 启动微信入口桥（监控 → [微信输入] → 大脑）
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

export LD_LIBRARY_PATH="${DIR}/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:${LD_LIBRARY_PATH:-}"
export LUA_PATH="${DIR}/lua/?.lua;${DIR}/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="${DIR}/lib/?.so;/usr/local/lualib/?.so;;"
export DISPLAY="${DISPLAY:-:0}"
export AGENT_URL="${AGENT_URL:-http://localhost:4097}"
export WECHAT_POLL_SEC="${WECHAT_POLL_SEC:-15}"
export WECHAT_SENT_LOG="${WECHAT_SENT_LOG:-/tmp/myagent_wechat_sent.log}"

# 常驻 RapidOCR 服务（模型只加载一次，桥通过本地 HTTP 调用）
if ! (echo >/dev/tcp/127.0.0.1/8799) 2>/dev/null; then
    setsid /data/venv/bin/python "${DIR}/ocr_rapidd.py" >/tmp/myagent_rapidd.log 2>&1 &
    for _ in $(seq 1 25); do
        (echo >/dev/tcp/127.0.0.1/8799) 2>/dev/null && break
        sleep 1
    done
fi

exec luajit "${DIR}/bridge.lua"
