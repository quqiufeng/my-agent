#!/usr/bin/env bash
# voice/orb.sh — 启动桌面悬浮球控制面板
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/orb/orb"
if [ ! -x "$BIN" ]; then
    echo "[orb] 编译..." >&2
    make -C "$DIR/orb" || { echo "[orb] 编译失败（需要 libsdl2-dev）" >&2; exit 1; }
fi
export DISPLAY="${DISPLAY:-:0}"
exec "$BIN" "$@"
