#!/usr/bin/env bash
# tools/weibo.sh — 打开微博搜索指定明星/关键词，全屏截图发微信（LuaJIT 实现）
# @desc 微博搜索（浏览器打开微博搜索页并全屏截图发微信）
# @usage tools/weibo.sh <关键词> [--to 会话]
# @rule **打开微博搜索页(截图)**：说“打开微博 / 微博搜 <关键词>，要网页截图”→ `tools/weibo.sh <关键词>`（打开搜索页并全屏截图）。**要找/发某明星的图片** → 用 `weibo_imgs.sh`。
# @order 19
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"
exec luajit "$DIR/weibo.lua" "$@"
