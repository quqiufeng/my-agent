#!/usr/bin/env bash
# tools/camera.sh — 读摄像头视频流（抓一帧给 Agent 看，LuaJIT 实现）
# @desc 读摄像头(USB/RTSP/HLS/TP-Link)一帧给 Agent 读图：优先用常驻界面(Flutter)产出的实时帧，其次自抓；也可录像
# @usage tools/camera.sh [--usb N | --rtsp URL | --hls URL | --ezviz keting|menkou | --tplink] [--help] [--out 路径] [--live 秒] [--bg]
# @rule 要看摄像头画面 → `tools/camera.sh`（返回图片路径，可直接读图）；要一段视频 → `--live <秒>`。
# @order 35
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/camera.lua" "$@"
