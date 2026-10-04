#!/usr/bin/env bash
# voice/app.sh — 统一界面（画面 + 人脸门控 + 语音监听 + 状态栏）
# 用法: app.sh [--no-audio] [--no-face-gate] [--no-forward]
#              [--usb N] [--rtsp URL] [--usb-only|--rtsp-only] [--size WxH]
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.sh
. "$DIR/config.sh" 2>/dev/null || true

BIN="$DIR/app/app"
if [ ! -x "$BIN" ] || [ "${1:-}" = "--build" ]; then
    echo "[app] 编译..." >&2
    make -C "$DIR/app" || { echo "[app] 编译失败（需要 libsdl2-dev libopencv-dev libasound2-dev）" >&2; exit 1; }
    [ "${1:-}" = "--build" ] && shift
fi
exec "$BIN" "$@"
