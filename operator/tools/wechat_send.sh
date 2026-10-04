#!/usr/bin/env bash
# tools/wechat_send.sh — 发送微信文本
# 用法: wechat_send.sh "内容"                  # 默认发到当前会话（文件传输助手）
#       wechat_send.sh --to 小王 "内容"        # 先搜索联系人再发送
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

TO=""
if [ "${1:-}" = "--to" ]; then TO="${2:-}"; shift 2; fi
TEXT="${*:-}"
if [ -z "$TEXT" ]; then echo "用法: wechat_send.sh [--to 联系人] 文本" >&2; exit 2; fi

export LD_LIBRARY_PATH="/opt/my-agent/wechat-ocr/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:${LD_LIBRARY_PATH:-}"
export LUA_PATH="/opt/my-agent/wechat-ocr/?.lua;/opt/my-agent/wechat-ocr/lua/?.lua;/opt/my-agent/wechat-ocr/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;"
export DISPLAY="${DISPLAY:-:0}"

WECHAT_TO="$TO" exec luajit "$DIR/wechat_send.lua" "$TEXT"
