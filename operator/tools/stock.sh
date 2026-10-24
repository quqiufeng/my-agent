#!/usr/bin/env bash
# tools/stock.sh — 股票行情/估值/财务（同花顺金融数据 API / fuyao.aicubes.cn，LuaJIT 实现）
# @desc 股票查询：行情快照 / 历史K线 / 估值 / 财务指标（同花顺数据源）
# @usage tools/stock.sh <名称或代码> | kline <名称或代码> [天数] | value <名称或代码> | fin <名称或代码> [报告期如2024-4] | list
# @rule **查股价/财务数据**：说“<股票>股价/多少钱/涨跌”→ `tools/stock.sh <名称或代码>`；“走势/K线”→ `kline <名称或代码> [天数]`；“估值/市盈率/市净率”→ `value <名称或代码>`；“财务/利润/ROE/毛利率”→ `fin <名称或代码> [报告期]`；“自选股”→ `list`。若用户要**看行情网页/截图/看盘** → 用 `quote_web.sh`。
# @order 16
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/stock.lua" "$@"
