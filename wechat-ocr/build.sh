#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"

echo "=== Building WeChat OCR Monitor ==="

# Configure
cmake -S "${PROJECT_DIR}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib/cmake"

# Build
cmake --build "${BUILD_DIR}" -j$(nproc)

echo ""
echo "=== Build complete ==="
echo "Binary: ${BUILD_DIR}/wechat-ocr"
echo "Run:    LD_LIBRARY_PATH=/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib ${BUILD_DIR}/wechat-ocr"
