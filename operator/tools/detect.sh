#!/usr/bin/env bash
# tools/detect.sh — 对摄像头抓帧做 YOLO 目标识别（原生 C++/libtorch，LuaJIT 调度）
# @desc 对摄像头抓帧做 YOLO 目标识别（**原生 C++/libtorch**，无 Python）：框出人/物并返回带框图路径
# @usage tools/detect.sh [--src usb|keting|menkou|<图片路径>] [--grid] [--conf 0.35] [--to 会话]
# @rule 说“看看家里有谁 / 门前有人吗 / 四个摄像头哪里有人”→ tools/detect.sh --grid（四路拼图后识别并按摄像头报告人数）；单路用 --src keting|menkou；要发回用 --to
# @order 46
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/detect.lua" "$@"
