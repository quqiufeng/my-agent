#!/usr/bin/env bash
# tools/vacuum.sh — 控制科沃斯扫地机 DEEBOT（原生 C 内核，LuaJIT 调度）
# @desc 控制科沃斯扫地机 DEEBOT（**原生 C 内核**，无 Python）：清扫/回充/找机/吸力/水量/音量/次数/续扫/AI/地毯/高级模式；并读电量/故障/网络/统计
# @usage tools/vacuum.sh <cmd> [arg]
#   status|battery|error|netinfo|stats|total|lifespan|logs
#   start|edge|spot|stop|pause|resume|dock|find
#   fan <quiet|normal|max|maxplus> | water <low|medium|high|ultra>
#   count <n> | volume <n> | continuous <0|1> | truedetect <0|1> | carpet <0|1> | advanced <0|1>
# @rule 用户说“扫地/开始扫地”→ start；“沿边”→ edge；“定点”→ spot；“停”→ stop；“回充”→ dock；“找一下扫地机/它在哪”→ find；“开大吸力/静音”→ fan max|quiet；“地毯增压”→ carpet 1；“扫地机状态/电量/统计”→ status|battery|stats|total
# @order 45
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/vacuum.lua" "$@"
