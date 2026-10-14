#!/usr/bin/env bash
# tools/iso_native.sh — 调用独立的等距图引擎(~iso_flutter)出图/动画 → 发微信
# @desc 等距解释图/动画：调用 `~/iso_flutter/bin/iso.sh`（native：Dart+Lua 引擎，Flutter 离屏渲染）生成 PNG/GIF/MP4，再发微信。引擎/图/设计规范都在 `~/iso_flutter`，本工具只做"调用 + 发微信"。
# @usage tools/iso_native.sh render <图名> [--ss N] [--lift 0..1] [--theme dark|light] [--out 目录] [--to 会话] [--no-send]
# @usage tools/iso_native.sh anim   <图名> [--frames N] [--ss N] [--motion] [--theme ..] [--out 目录] [--to 会话] [--no-send]
# @rule **等距图**：引擎/图/规范都在独立仓 **~/iso_flutter**（框架 `iso_engine` + 应用 `app`）；本工具只是"调用它 + 发微信"。图名见 `~/iso_flutter/app/lib/main.dart` 的 `_figures`（`tmall-genie`(Lua) / `tmall-genie-dart`(Dart) / `lathe` / `tube`）。新增/改图在 ~/iso_flutter 里做（Lua：`app/lib/lua/figures/*.lua`；Dart：`main.dart`），再 `cd ~/iso_flutter/app && flutter build linux --release`。
# @order 31
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ISO="${ISO_FLUTTER:-$HOME/iso_flutter}/bin/iso.sh"
TO=""; SEND=1; ARGS=()
while [ $# -gt 0 ]; do case "$1" in
  --to) TO="$2"; shift 2 ;; --no-send) SEND=0; shift ;; *) ARGS+=("$1"); shift ;; esac; done
[ -x "$ISO" ] || { echo "找不到等距图引擎入口：$ISO（~/iso_flutter/bin/iso.sh）" >&2; exit 1; }

OUT="$("$ISO" "${ARGS[@]}")" || { echo "$OUT" >&2; exit 1; }
FILE="$(printf '%s\n' "$OUT" | tail -1)"
[ -f "$FILE" ] || { echo "未生成文件（输出：$OUT）" >&2; exit 1; }
echo "生成: $FILE"
if [ "$SEND" = 1 ]; then
  if [ -n "$TO" ]; then "$DIR/wechat_send_file.sh" "$FILE" --to "$TO" >/dev/null 2>&1; else "$DIR/wechat_send_file.sh" "$FILE" >/dev/null 2>&1; fi
  echo "已发送 -> ${TO:-文件传输助手}"
fi
