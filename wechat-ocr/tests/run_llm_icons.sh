#!/bin/bash
set -e
cd /opt/my-agent/wechat-ocr
export LD_LIBRARY_PATH="./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:/opt/my-agent/joycaption-wrapper:/opt/llama.cpp/build/bin"
export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/usr/local/lualib/?.so;;"
exec luajit tests/test_llm_icons.lua "$@"
