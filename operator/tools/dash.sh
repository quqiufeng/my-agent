#!/usr/bin/env bash
# tools/dash.sh — 股票大屏：汇总指数 + 自选股 + 主指数K线，渲染「点阵风」大屏图并发微信（LuaJIT 实现）
# @desc 股票大屏（点阵风·暗色：指数环+自选股+小K线）
# @usage tools/dash.sh [--to 会话] [--show] [--no-send]
# @rule **自绘数据大屏**：说“自绘大屏 / 汇总我的自选股 / 把指数和自选股汇总成一张图”→ `tools/dash.sh`。若只是“看行情/看盘”→ 用 `quote_web.sh` 开浏览器截图。
# @order 17
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/dash_cli.lua" "$@"
