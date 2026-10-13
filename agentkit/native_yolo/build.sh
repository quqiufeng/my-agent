#!/usr/bin/env bash
# build.sh — 编译 YOLO 原生检测器（libtorch + OpenCV）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TORCH="${TORCH_PATH:-/data/venv/lib/python3.12/site-packages/torch}"
g++ -O2 -std=c++17 "$HERE/yolo_detect.cpp" -o "$HERE/yolo_detect" \
  -I"$TORCH/include" -I"$TORCH/include/torch/csrc/api/include" \
  -L"$TORCH/lib" -ltorch -ltorch_cpu -lc10 -Wl,-rpath,"$TORCH/lib" \
  $(pkg-config --cflags --libs opencv4)
echo "built: $HERE/yolo_detect"
