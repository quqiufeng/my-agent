#!/bin/bash
set -e
cd /opt/my-agent/wechat-ocr
export LD_LIBRARY_PATH="./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib"
exec luajit tests/test_hover_tooltip.lua "$@"
