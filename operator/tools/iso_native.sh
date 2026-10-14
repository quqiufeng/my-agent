#!/usr/bin/env bash
# tools/iso_native.sh — 等距图 **native(Flutter) 引擎**出图/出动画 → 发微信（无浏览器、无 node）
# @desc 等距解释图（native 版）：Flutter app 离屏渲染（Dart + Lua 引擎）→ PNG；`anim` → GIF/MP4。无浏览器、无 node。
# @usage tools/iso_native.sh render <图名> [--ss N] [--lift X] [--out 目录] [--to 会话] [--no-send]
# @usage tools/iso_native.sh anim   <图名> [--frames N] [--ss N] [--motion] [--out 目录] [--to 会话] [--no-send]
# @rule **图名**：`tmall-genie`（天猫精灵，Lua 定义）/`lathe`/`tube`（见 `~/iso_flutter/app/lib/main.dart` 的 `_figures`）。图可用 Dart 写或 Lua 写（`lib/lua/figures/*.lua`）。改图后需 `cd ~/iso_flutter/app && flutter build linux --release`。
# @order 31
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="${ISO_NATIVE_BIN:-$HOME/iso_flutter/app/build/linux/x64/release/bundle/iso_app}"
DISP="${DISPLAY:-:0}"
FF="$(command -v ffmpeg || true)"

usage(){ echo "用法: iso_native.sh render <图名> [--ss N] [--lift X] [--out 目录] [--to 会话] [--no-send]" >&2
         echo "      iso_native.sh anim   <图名> [--frames N] [--ss N] [--motion] [--out 目录] [--to 会话] [--no-send]" >&2; exit 2; }
CMD="${1:-render}"; shift || true; case "$CMD" in render|anim) ;; *) usage ;; esac
FIG="${1:-}"; shift || true; [ -n "$FIG" ] || usage

OUTD="/tmp/opencode"; TO=""; SEND=1; SS=2; LIFT=""; FRAMES=120; MOTION=0
while [ $# -gt 0 ]; do case "$1" in
  --out) OUTD="$2"; shift 2 ;; --to) TO="$2"; shift 2 ;; --ss) SS="$2"; shift 2 ;;
  --lift) LIFT="$2"; shift 2 ;; --frames) FRAMES="$2"; shift 2 ;; --motion) MOTION=1; shift ;; --no-send) SEND=0; shift ;;
  -*) shift ;; *) shift ;;
esac; done

[ -x "$BIN" ] || { echo "找不到 native 程序：$BIN（先 cd ~/iso_flutter/app && flutter build linux --release）" >&2; exit 1; }
mkdir -p "$OUTD"
send(){ if [ -n "$TO" ]; then "$DIR/wechat_send_file.sh" "$1" --to "$TO" >/dev/null 2>&1; else "$DIR/wechat_send_file.sh" "$1" >/dev/null 2>&1; fi; echo "已发送 -> ${TO:-文件传输助手}"; }

ENVS=(DISPLAY="$DISP" ISO_EXPORT="$FIG" ISO_SS="$SS")
[ -n "$LIFT" ] && ENVS+=(ISO_LIFT="$LIFT")
[ "$MOTION" = 1 ] && ENVS+=(ISO_MOTION=1)
one(){ env "${ENVS[@]}" ISO_FRAME="$1" ISO_N="$2" ISO_OUT="$3" timeout 60 "$BIN" >/dev/null 2>&1; }

case "$CMD" in
  render)
    PNG="$OUTD/${FIG}_native.png"
    one 0 1 "$PNG"
    [ -f "$PNG" ] || { echo "出图失败（图名 $FIG 是否存在？）" >&2; exit 1; }
    echo "出图: $PNG"
    [ "$SEND" = 1 ] && send "$PNG"
    ;;
  anim)
    [ -n "$FF" ] || { echo "需要 ffmpeg" >&2; exit 1; }
    FD="$OUTD/${FIG}_frames"; rm -rf "$FD"; mkdir -p "$FD"
    # 一次进程内渲染所有帧（ISO_BATCH，快）
    env "${ENVS[@]}" ISO_BATCH=1 ISO_N="$FRAMES" ISO_OUT="$FD" timeout 600 "$BIN" >/dev/null 2>&1
    GIF="$OUTD/${FIG}_native.gif"; MP4="$OUTD/${FIG}_native.mp4"
    ffmpeg -y -framerate 60 -i "$FD/f%04d.png" -vf "scale=iw:ih:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "$GIF" >/dev/null 2>&1
    ffmpeg -y -framerate 60 -i "$FD/f%04d.png" -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$MP4" >/dev/null 2>&1
    echo "出动画: $GIF / $MP4"
    [ "$SEND" = 1 ] && send "$GIF"
    ;;
esac
