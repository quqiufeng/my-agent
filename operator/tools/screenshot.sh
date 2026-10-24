#!/usr/bin/env bash
# tools/screenshot.sh — 截屏：只截本机全屏并返回路径（LuaJIT 实现）
# @desc 只截本机全屏并返回路径，不发送；摄像头拼图用 camera_grid.sh
# @usage tools/screenshot.sh [输出路径]
# @rule **只截本机全屏** → `screenshot.sh`（返回路径，不发）；要直接发微信用 `wechat_shot.sh`；四个摄像头拼图用 `camera_grid.sh`。
# @order 6
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/screenshot.lua" "$@"
