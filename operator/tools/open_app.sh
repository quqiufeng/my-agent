#!/usr/bin/env bash
# tools/open_app.sh — 打开白名单内的本机应用
# 用法: open_app.sh <chrome|terminal|files|editor|wechat>
set -uo pipefail
export DISPLAY="${DISPLAY:-:0}"
APP="${1:-}"
case "$APP" in
    chrome|google-chrome) setsid google-chrome >/dev/null 2>&1 & ;;
    terminal|xterm)       setsid xterm     >/dev/null 2>&1 & ;;
    files|nautilus)       setsid nautilus  >/dev/null 2>&1 & ;;
    editor|code)          setsid code      >/dev/null 2>&1 & ;;
    wechat)               setsid /opt/wechat/wechat >/dev/null 2>&1 & ;;
    *)
        echo "不支持的应用: ${APP:-空}（可用: chrome terminal files editor wechat）" >&2
        exit 2
        ;;
esac
sleep 1
echo "已打开 $APP"
