#!/usr/bin/env bash
# tools/listen_cam.sh — 监听萤石摄像头麦克风（从直播流抽 AAC 音频，LuaJIT 实现）
# @desc 监听萤石摄像头麦克风（从直播流抽 AAC 音频）：播放到本机音响，或录成 wav
# @usage tools/listen_cam.sh [keting|menkou] [秒数=10] [--save <路径>] [--play] [--bg]
# @rule 说“听听客厅/门口的声音/有没有动静”→ tools/listen_cam.sh keting 10（默认外放）；只想存文件用 --save
# @order 47
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/listen_cam.lua" "$@"
