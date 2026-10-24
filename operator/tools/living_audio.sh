#!/usr/bin/env bash
# tools/living_audio.sh — 在客厅小机箱的 3.5mm 小音响播放音频（LuaJIT/终端执行）
# @desc 客厅小音响播放音频；文本在本机 TTS 合成后 scp 到小机箱，由 VLC 输出到 3.5mm 小音响
# @usage tools/living_audio.sh say <文本> | play <本地文件|http(s) URL> | stop
# @rule 说“客厅/小机箱/小音响 说话/播放音频/放这段声音”→ `say <文本>` 或 `play <文件/URL>`；停止→`stop`。
# @order 49
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/living_audio.lua" "$@"
