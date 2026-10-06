#!/usr/bin/env bash
# tools/screenshot.sh — 截屏（默认全屏），返回图片路径
# @rule **截屏**：说“截个屏/截屏发我”→ `screenshot.sh`（返回路径），再用 `wechat_send_file.sh <路径> [--to 来源会话]` 发回。
# @order 6
# 方式：触发系统 Print 键（screengrab，已开启自动保存到 defDir，默认 ~/Pictures），
#       取最新生成的图片；失败则回退 ImageMagick 全屏抓图。
# 用法: screenshot.sh [可选输出路径]
set -uo pipefail
export DISPLAY="${DISPLAY:-:0}"

CONF="$HOME/.config/screengrab/screengrab.conf"
SAVE_DIR="$(sed -n 's/^defDir=//p' "$CONF" 2>/dev/null)"
[ -z "${SAVE_DIR:-}" ] && SAVE_DIR="$HOME/Pictures"
mkdir -p "$SAVE_DIR" 2>/dev/null

MARK="$(mktemp)"

# 触发系统截图（Print 键 = screengrab 自动保存）
xdotool key --clearmodifiers Print 2>/dev/null

# 等新文件出现（最多约 6 秒）
for _ in $(seq 1 12); do
    newest="$(ls -t "$SAVE_DIR"/*.png "$SAVE_DIR"/*.jpg 2>/dev/null | head -1)"
    if [ -n "${newest:-}" ] && [ "$newest" -nt "$MARK" ]; then
        rm -f "$MARK"
        sleep 0.5
        for _ in 1 2 3; do wmctrl -c ScreenGrab 2>/dev/null; sleep 0.3; done  # 关掉 screengrab 窗口
        if [ -n "${1:-}" ]; then cp -f "$newest" "$1" && echo "$1"; else echo "$newest"; fi
        exit 0
    fi
    sleep 0.5
done
rm -f "$MARK"
wmctrl -c ScreenGrab 2>/dev/null

# 兜底：直接全屏抓图
OUT="${1:-/tmp/myagent_shot_$(date +%Y%m%d_%H%M%S).png}"
if import -window root "$OUT" 2>/dev/null; then echo "$OUT"; exit 0; fi
echo "截屏失败" >&2; exit 1
