#!/usr/bin/env bash
# tools/phone_music.sh — 打开手机「汽水音乐」并把声音转到客厅小音响（LuaJIT/终端执行）
# @desc 手机汽水音乐播放：确保手机音频转发到小机箱小音响，打开汽水音乐并开始播放
# @usage tools/phone_music.sh play | stop
# @rule 说“打开汽水音乐/手机放汽水音乐/用手机听歌/汽水音乐播放”→ play；停止转发→stop（手机播放/暂停由手机自己控制）。
# @order 51
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/phone_music.lua" "$@"
