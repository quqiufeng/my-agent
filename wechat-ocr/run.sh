#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure shared library is findable
export LD_LIBRARY_PATH="${PROJECT_DIR}/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:${LD_LIBRARY_PATH}"

# Add Lua module paths (repo sources take precedence over system copies)
export LUA_PATH="${PROJECT_DIR}/lua/?.lua;${PROJECT_DIR}/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;${LUA_PATH}"
export LUA_CPATH="${PROJECT_DIR}/lib/?.so;/usr/local/lualib/?.so;${LUA_CPATH}"

cd "${PROJECT_DIR}"

echo "Starting WeChat OCR Monitor..."
echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH}"
echo "LUA_PATH=${LUA_PATH}"
echo ""

/usr/local/bin/luajit "${PROJECT_DIR}/lua/wechat_monitor.lua"
