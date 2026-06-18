#!/bin/bash
# Build the C shared library
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "=== Building wechat-ocr shared library ==="

mkdir -p build_lib
cmake -S . -B build_lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib/cmake"

cmake --build build_lib -j$(nproc) --target wechat_ocr_core

echo ""
echo "=== Done ==="
echo "Library: lib/libwechat_ocr_core.so"
echo ""
echo "Run: ./run.sh"
