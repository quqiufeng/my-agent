#!/usr/bin/env bash
# tools/say_cam.sh — 让萤石摄像头喇叭播放一段音频（LuaJIT 实现）
# @desc 让萤石摄像头喇叭播放一段音频（对讲/喊话/播报）：上传音频到萤石 → 设备播放
# @usage tools/say_cam.sh [keting|menkou] <音频.wav>
# @rule 说“对客厅喊话 / 让门口响一下 / 往客厅播报”→ tools/say_cam.sh keting <wav>（**需已开通萤石「语音提醒」资源包**，否则返回 111000）
# @order 48
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/say_cam.lua" "$@"
