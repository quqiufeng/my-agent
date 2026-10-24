#!/usr/bin/env bash
# tools/camera_grid.sh — 四路摄像头各截一张，拼成 2×2 发微信（LuaJIT 实现）
# @desc 抓 EZVIZ 客厅/门口、TP-Link、USB 四路画面，拼图发送微信
# @usage tools/camera_grid.sh [--to 会话] [--no-send] [--out 路径]
# @rule 说“摄像头截图发我 / 摄像头 截图发我 / 四个摄像头拼图 / 看看家里四个画面”→ `tools/camera_grid.sh`（默认发文件传输助手）；只生成不发用 `--no-send`。
# @order 36
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/camera_grid.lua" "$@"
