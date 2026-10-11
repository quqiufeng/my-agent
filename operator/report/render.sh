#!/usr/bin/env bash
# operator/report/render.sh — 用 headless Chrome 把 Kami 报告 HTML 渲染成 PNG/PDF
# @desc 把 report/*.html 渲染为 PNG（或 PDF），用于排版好的日报/简报
# @usage report/render.sh <in.html> <out.png|.pdf> [width]
# @rule 出“排版好的日报/简报/报告图” → 用 `report/render.sh`（Kami 排版）。
# @order 40
set -uo pipefail
IN="${1:?用法: render.sh <in.html> <out.png|.pdf> [width]}"
OUT="${2:?缺输出路径}"
W="${3:-820}"
CHROME="$(command -v google-chrome || command -v google-chrome-stable || command -v chromium || command -v chromium-browser)"
[ -n "$CHROME" ] || { echo "未找到 Chrome/Chromium" >&2; exit 3; }
case "$OUT" in
  *.pdf) "$CHROME" --headless=new --disable-gpu --no-sandbox --no-pdf-header-footer \
           --print-to-pdf="$OUT" "file://$IN" >/dev/null 2>&1 ;;
  *)     "$CHROME" --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
           --default-background-color=00000000 \
           --window-size="$W,3000" --screenshot="$OUT" "file://$IN" >/dev/null 2>&1
         # 裁掉底部空白视口，再补米纸边距，得到贴合内容的图
         command -v convert >/dev/null && \
           convert "$OUT" -trim +repage -bordercolor '#f5f4ed' -border 64x56 "$OUT" 2>/dev/null || true ;;
esac
[ -s "$OUT" ] && echo "$OUT" || { echo "渲染失败" >&2; exit 1; }
