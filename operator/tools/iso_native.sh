#!/usr/bin/env bash
# tools/iso_native.sh — 调用独立的等距图引擎(~iso_flutter)出图/动画 → 发微信（LuaJIT 实现）
# @desc 等距解释图/动画：调用 `~/iso_flutter/bin/iso.sh`（native：Dart+Lua 引擎，Flutter 离屏渲染）生成 PNG/GIF/MP4，再发微信。**不是文生图**：只能渲染 `~/iso_flutter` 里已注册/已写好的图脚本；新图必须先写 Lua/Dart 图脚本并重新构建。
# @usage tools/iso_native.sh render <图名> [--ss N] [--lift 0..1] [--theme dark|light] [--out 目录] [--to 会话] [--no-send]
# @usage tools/iso_native.sh anim   <图名> [--frames N] [--ss N] [--motion] [--theme ..] [--out 目录] [--to 会话] [--no-send]
# @rule **等距图/动画（非文生图）**：只能渲染 `~/iso_flutter` 里已注册的图；不能按提示词即时生成新图。引擎/图/规范都在独立仓 **~/iso_flutter**（框架 `iso_engine` + 应用 `app`）；本工具只是"调用它 + 发微信"。图名见 `~/iso_flutter/app/lib/main.dart` 的 `_figures`（`tmall-genie`(Lua) / `tmall-genie-dart`(Dart) / `lathe` / `tube`）。新增/改图在 ~/iso_flutter 里做（Lua：`app/lib/lua/figures/*.lua`；Dart：`main.dart`），再 `cd ~/iso_flutter/app && flutter build linux --release`。
# @order 31
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/iso_native.lua" "$@"
