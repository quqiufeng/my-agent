#!/usr/bin/env bash
# tools/listen_cam.sh — 监听摄像头/本机麦克风（EZVIZ HLS / TP-Link RTSP / USB ALSA，LuaJIT 实现）
# @desc 监听音频来源（EZVIZ/TP-Link/本机USB麦克风）：播放到本机音响，或录成 wav
# @usage tools/listen_cam.sh [keting|menkou|tplink|usb] [秒数=10] [--save <路径>] [--play] [--bg]
# @rule 说“听听客厅/门口/TP-Link/本机麦克风的声音/有没有动静”→ tools/listen_cam.sh keting|menkou|tplink|usb 10（默认外放）；只想存文件用 --save
# @order 47
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/listen_cam.lua" "$@"
