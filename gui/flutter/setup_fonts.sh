#!/usr/bin/env bash
# setup_fonts.sh — 复用字体（体积大，不入库）。默认从 WordCard 复制，可用 WC_FONTS 覆盖。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; DST="$HERE/assets/fonts"; mkdir -p "$DST"
SRC="${WC_FONTS:-/opt/WordCard/gui/flutter/assets/fonts}"
for f in MapleMono-NF-CN-Regular.ttf MapleMono-NF-CN-Medium.ttf MapleMono-NF-CN-SemiBold.ttf MapleMono-NF-CN-Bold.ttf TsangerJinKai02-W04.ttf TsangerJinKai02-W05.ttf; do
  [ -f "$DST/$f" ] || cp "$SRC/$f" "$DST/$f"
done
echo "字体就绪：$DST"
