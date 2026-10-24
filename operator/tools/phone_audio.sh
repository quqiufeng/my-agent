#!/usr/bin/env bash
# tools/phone_audio.sh — 手机音频转发到客厅小音响（scrcpy 音频，LuaJIT/终端执行）
# @desc 把 USB 连接手机的播放音频经 scrcpy 转发到小机箱 3.5mm 小音响；手机继续自己控制播放/暂停
# @usage tools/phone_audio.sh start | stop | status
# @rule 说“手机声音转到小音响/开手机音频/关手机音频”→ start/stop；只转发音频，不控制手机播放。
# @order 50
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/phone_audio.lua" "$@"
