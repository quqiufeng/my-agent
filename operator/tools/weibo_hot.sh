#!/usr/bin/env bash
# tools/weibo_hot.sh — 微博热搜 → Kami 排版图 + 文字，发微信（LuaJIT 实现）
# @desc 抓微博实时热搜榜，生成排版图并（可选）发文字到微信（默认文件传输助手）
# @usage tools/weibo_hot.sh [--to 会话] [--limit N（默认15）] [--display] [--no-send]
# @rule 用户说“微博热 / 微博热搜 / 微博热搜榜” → `tools/weibo_hot.sh`（默认出图+发微信）；要**只要文本**加 `--display`。
# @order 22
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/weibo_hot.lua" "$@"
