#!/usr/bin/env bash
# tools/google_search.sh — 谷歌搜索/新闻 → Kami 排版图 + 文字，发微信（AI 助手用）
# @desc 用 Chrome(CDP/DOM) 谷歌搜索，先生成排版图再发文字到微信（默认文件传输助手）
# @usage tools/google_search.sh <关键词> [--news] [--to 会话] [--no-image] [--no-send]
# @rule 用户说“帮我 google 搜索/查一下 <关键词> 并发我微信” → `tools/google_search.sh "<关键词>"`（默认发图+文字）；查新闻加 `--news`。
# @order 29
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT="/opt/my-agent/operator/report"

KW=""; NEWS=0; TO="文件传输助手"; IMG=1; SEND=1
while [ $# -gt 0 ]; do
  case "$1" in
    --news) NEWS=1; shift ;;
    --to) TO="${2:-文件传输助手}"; shift 2 ;;
    --no-image) IMG=0; shift ;;
    --no-send) SEND=0; shift ;;
    *) [ -z "$KW" ] && KW="$1"; shift ;;
  esac
done
[ -n "$KW" ] || { echo "用法: google_search.sh <关键词> [--news] [--to 会话]" >&2; exit 2; }

# 图形会话环境
if [ -z "${XAUTHORITY:-}" ] && [ -z "${DISPLAY:-}" ]; then
  P=$(pgrep -x pcmanfm-qt | head -1)
  [ -n "$P" ] && XAUTHORITY=$(tr '\0' '\n' < "/proc/$P/environ" 2>/dev/null | sed -n 's/^XAUTHORITY=//p')
fi
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-}"

# 1) 确保专用 Chrome 实例在跑
ss -ltn 2>/dev/null | grep -q ':9222 ' || "$DIR/chrome_debug.sh" >/dev/null 2>&1

# 2) 一次搜索：产出 HTML + 文本
STAMP="$(date +%Y%m%d_%H%M%S)"; OUT="/tmp/myagent_google_${STAMP}"
MODE=$([ "$NEWS" = 1 ] && echo news || echo search)
luajit "$REPORT/google_report.lua" "$OUT.html" "$OUT.txt" "$KW" "$MODE" 2>/dev/null || true
[ -s "$OUT.txt" ] || { echo "未取到结果" >&2; exit 1; }

# 3) 先生成图（Kami），优先发图
if [ "$IMG" = 1 ]; then
  "$REPORT/render.sh" "$OUT.html" "$OUT.png" 820 >/dev/null 2>&1
  echo "图片: $OUT.png"
fi
cat "$OUT.txt"

# 4) 发送：先图后文
if [ "$SEND" = 1 ]; then
  if [ "$IMG" = 1 ] && [ -s "$OUT.png" ]; then
    "$DIR/wechat_send_file.sh" "$OUT.png" --to "$TO" >/dev/null 2>&1 && echo "已发图 → $TO"
    sleep 1
  fi
  "$DIR/wechat_send.sh" --to "$TO" "$(cat "$OUT.txt")" >/dev/null 2>&1 && echo "已发文字 → $TO"
fi
