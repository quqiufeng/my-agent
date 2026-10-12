#!/usr/bin/env bash
# tools/gemini.sh — 问 Google AI(Gemini) → 默认出图+发微信；--display 只输出文本（供其它 agent）
# @desc 用 Chrome(CDP) 问 Google AI(Gemini)；默认排版图+文字发微信，--display 仅打印回答
# @usage tools/gemini.sh <问题> [--display] [--to 会话] [--no-image] [--no-send]
# @rule 用户说“问 Google AI / 问 Gemini / 让 AI 回答 <问题> 并发我微信” → `tools/gemini.sh "<问题>"`；要**只要文本**供程序用 → 加 `--display`。
# @order 28
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT="/opt/my-agent/operator/report"

Q=""; TO="文件传输助手"; IMG=1; SEND=1; DISP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --display) DISP=1; IMG=0; SEND=0; shift ;;
    --to) TO="${2:-文件传输助手}"; shift 2 ;;
    --no-image) IMG=0; shift ;;
    --no-send) SEND=0; shift ;;
    *) [ -z "$Q" ] && Q="$1"; shift ;;
  esac
done
[ -n "$Q" ] || { echo "用法: gemini.sh <问题> [--display] [--to 会话]" >&2; exit 2; }

if [ -z "${XAUTHORITY:-}" ] && [ -z "${DISPLAY:-}" ]; then
  P=$(pgrep -x pcmanfm-qt | head -1)
  [ -n "$P" ] && XAUTHORITY=$(tr '\0' '\n' < "/proc/$P/environ" 2>/dev/null | sed -n 's/^XAUTHORITY=//p')
fi
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-}"

# 1) 确保专用 Chrome 实例在跑
ss -ltn 2>/dev/null | grep -q ':9222 ' || "$DIR/chrome_debug.sh" >/dev/null 2>&1

# 2) 问 Gemini（单连接；失败重试）
STAMP="$(date +%Y%m%d_%H%M%S)"; OUT="/tmp/myagent_gemini_${STAMP}"
for try in 1 2 3; do
  timeout 120 node /opt/my-agent/agentkit/tools/gemini.js "$Q" > "$OUT.ans" 2>/dev/null
  [ -s "$OUT.ans" ] && break
  echo "第${try}次未取到，重试..." >&2; sleep 2
done
ANS="$(cat "$OUT.ans" 2>/dev/null)"
[ -n "$ANS" ] || { echo "未取到 Google AI 回答" >&2; exit 1; }

# --display：只输出文本，供其它 agent 使用
if [ "$DISP" = 1 ]; then printf '%s\n' "$ANS"; exit 0; fi
echo "$ANS"

# 3) 生成 Kami 图
luajit "$REPORT/gemini_report.lua" "$OUT.html" "$OUT.txt" "$Q" "$OUT.ans" 2>/dev/null
if [ "$IMG" = 1 ]; then
  "$REPORT/render.sh" "$OUT.html" "$OUT.png" 820 >/dev/null 2>&1
  echo "图片: $OUT.png"
fi

# 4) 发送：先图后文
if [ "$SEND" = 1 ]; then
  if [ "$IMG" = 1 ] && [ -s "$OUT.png" ]; then
    "$DIR/wechat_send_file.sh" "$OUT.png" --to "$TO" >/dev/null 2>&1 && echo "已发图 → $TO"
    sleep 3
  fi
  "$DIR/wechat_send.sh" --to "$TO" "$(cat "$OUT.txt")" >/dev/null 2>&1 && echo "已发文字 → $TO"
fi
