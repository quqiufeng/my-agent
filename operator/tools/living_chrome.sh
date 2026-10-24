#!/usr/bin/env bash
# tools/living_chrome.sh — 在客厅小机箱的 Chrome 打开指定网页（LuaJIT/终端执行）
# @desc 远程控制客厅小机箱 Chrome 打开网页（小机箱 HDMI 输出到 Sony 电视）
# @usage tools/living_chrome.sh open <http/https URL>
# @rule 说“客厅电视/小机箱打开网页/放某个网页” → tools/living_chrome.sh open <URL>；只允许 http/https。
# @order 48
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/living_chrome.lua" "$@"
