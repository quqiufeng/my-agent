#!/usr/bin/env bash
# tools/image.sh — 生成图片并发送到微信（LuaJIT 实现）
# @desc 生成图片并发送到微信（可指定 小红书/小红薯、朋友圈 尺寸）
# @usage tools/image.sh [小红书|小红薯|朋友圈] "提示词" [--to 会话] [--force] [--fg]
# @rule **画图/生成图片**：说“画一张…/生成图片…/来个…的图”→ `image.sh "提示词"`。尺寸可**明确指定**：`小红书`/`小红薯`（3:4 竖版 1920×2560）、`朋友圈`（1:1 方图 2048×2048），默认 2560×1440 横版。用法 `image.sh [小红书|小红薯|朋友圈] "提示词"`。出图要几分钟，完成后脚本自动发微信，你只需简短确认。GPU 忙时会被拒绝，稍后再试。
# @order 8
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/image.lua" "$@"
