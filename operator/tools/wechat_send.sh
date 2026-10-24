#!/usr/bin/env bash
# tools/wechat_send.sh — 发送微信文本（LuaJIT + xdo/xclip 实现）
# 用法: wechat_send.sh "内容"                  # 默认发到当前会话（文件传输助手）
#       wechat_send.sh --to 小王 "内容"        # 先搜索联系人再发送
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"
exec luajit "$DIR/wechat_send.lua" "$@"
