#!/usr/bin/env bash
# tools/wechat_shot.sh — 截屏发微信（LuaJIT 实现）
# @desc 截屏发微信：说「截图/截屏 <应用名>」则截该应用；不给应用则截桌面。发送到指定会话/文件传输助手
# @usage tools/wechat_shot.sh [--to 会话] [--app 应用名]
# @rule **截屏发我 / 截图发我** → `tools/wechat_shot.sh`（不加 --app 截的是桌面）。**要截某个应用**（如“截图 agent / 助手 / 微信 / 浏览器”）→ **必须** `tools/wechat_shot.sh --app <应用名>`。
# @order 22
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"
exec luajit "$DIR/wechat_shot.lua" "$@"
