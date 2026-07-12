#!/bin/bash
set -e
cd /opt/my-agent/wechat-ocr
export LD_LIBRARY_PATH="./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:/opt/my-agent/joycaption-wrapper:/opt/llama.cpp/build/bin"
exec luajit tests/test_click_all_icons.lua "$@"
