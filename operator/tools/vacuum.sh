#!/usr/bin/env bash
# @desc 控制科沃斯扫地机 DEEBOT（**原生 C 内核**，无 Python）：开始/暂停/继续/停止清扫、归位回充、找机、看状态
# @usage tools/vacuum.sh <status|start|pause|resume|stop|dock|find>
# @rule 用户说“扫地/让扫地机扫/开始扫地”→ start；“停/别扫了”→ stop；“回充/回去充电”→ dock；“找一下扫地机/它在哪”→ find；“扫地机状态/在干嘛”→ status
# @order 45
set -uo pipefail
ENVF="${ECOVACS_ENV:-$HOME/.env}"
[ -f "$ENVF" ] && set -a && . "$ENVF" && set +a
BIN="${VACUUM_BIN:-/opt/my-agent/agentkit/native_vacuum/vacuum}"
if [ -x "$BIN" ]; then
  exec "$BIN" "$@"
fi
# 兜底：Python 版（若未编译原生）
exec "${VACUUM_PYTHON:-/data/venv/bin/python}" /opt/my-agent/agentkit/tools/vacuum.py "$@"
