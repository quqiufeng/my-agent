#!/usr/bin/env bash
# tools/chrome_auth.sh — Chrome 远程调试授权 + 受控状态（视觉 + MCP 结合，LuaJIT 实现）
# @desc 开启 Chrome「允许远程调试」并点掉授权弹窗（视觉）；`status` 查看是否受控
# @usage tools/chrome_auth.sh [enable|consent|watch <秒>|daemon|status]
# @rule 浏览器 MCP(chrome-devtools) 连不上/提示授权 → 先 `tools/chrome_auth.sh enable`；仍弹“同意”框用 `consent`，或后台常驻 `daemon`（持续点掉授权）；查状态用 `status`。
# @order 18
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
unset DISPLAY
exec luajit "$DIR/chrome_auth.lua" "$@"
