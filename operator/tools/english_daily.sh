#!/usr/bin/env bash
# tools/english_daily.sh — 每日英语：随机科技媒体文章 → Google AI 中英对照 → Kami 排版图 → 发微信（LuaJIT 实现）
# @desc 从多家科技媒体(HN/Ars/TechCrunch/Verge/Wired/Engadget/Register/BBC/MIT)每天随机取一篇英文 → Gemini 中英对照+生词 → 图文发微信（图底含原文来源 URL）
# @usage tools/english_daily.sh [<主题> | --url <url>] [--words N] [--level B1-B2] [--display] [--to 会话] [--no-send]
# @rule 用户说“每日英语 / 英语短文 / 学英语 / 来篇英语文章” → `tools/english_daily.sh`（默认随机科技媒体，出图+发微信）；只要文本加 `--display`。
# @order 24
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/english_daily.lua" "$@"
