#!/usr/bin/env bash
# tools/wechat_send_file.sh — 发送文件/图片到微信
# 用法: wechat_send_file.sh /path/to/file [--to 联系人]
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then echo "用法: wechat_send_file.sh <文件路径> [--to 联系人]" >&2; exit 2; fi
shift || true

TO=""
if [ "${1:-}" = "--to" ]; then TO="${2:-}"; fi

export LD_LIBRARY_PATH="/opt/my-agent/wechat-ocr/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:${LD_LIBRARY_PATH:-}"
export LUA_PATH="/opt/my-agent/wechat-ocr/?.lua;/opt/my-agent/wechat-ocr/lua/?.lua;/opt/my-agent/wechat-ocr/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;"
export DISPLAY="${DISPLAY:-:0}"

WECHAT_TO="$TO" exec luajit "$DIR/wechat_send_file.lua" "$FILE"
