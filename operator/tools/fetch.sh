#!/usr/bin/env bash
# tools/fetch.sh — 通用带 cookie 抓取（curl，不需要浏览器，LuaJIT 实现）
# @desc 用 curl 抓取网页/接口，可带 ~/.env 里的 cookie（登录态）
# @usage tools/fetch.sh <url> [--cookie ENVKEY] [--post DATA] [--json] [--save FILE] [--referer URL] [--header 'K: V'] [--ua UA]
# @rule **登录态抓取**（微博/知乎/某站资料）→ `tools/fetch.sh <url> --cookie <ENVKEY>`（cookie 先用 `cookie.sh save` 落盘）；**不要**为此开浏览器或 OCR 网页。
# @order 42
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/fetch.lua" "$@"
