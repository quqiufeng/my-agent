#!/usr/bin/env bash
# voice/camera.sh — 摄像头窗口
# 用法: camera.sh [--usb N] [--rtsp URL] [--usb-only|--rtsp-only] [--size WxH]
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.sh
. "$DIR/config.sh" 2>/dev/null || true

BIN="$DIR/camera/camera"
if [ ! -x "$BIN" ] || [ "${1:-}" = "--build" ]; then
    echo "[camera] 编译..." >&2
    make -C "$DIR/camera" || { echo "[camera] 编译失败（需要 libsdl2-dev libopencv-dev）" >&2; exit 1; }
    [ "${1:-}" = "--build" ] && shift
fi
exec "$BIN" "$@"
