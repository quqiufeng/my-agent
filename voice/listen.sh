#!/usr/bin/env bash
# voice/listen.sh — 启动语音入口（麦克风常驻监听）
# 用法: listen.sh [--once] [--no-forward]
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.sh
. "$DIR/config.sh"

BIN="$DIR/listen/listen"
if [ ! -x "$BIN" ]; then
    echo "[voice] 未编译，正在编译..." >&2
    make -C "$DIR/listen" || { echo "[voice] 编译失败（需要 libasound2-dev）" >&2; exit 1; }
fi
exec "$BIN" "$@"
