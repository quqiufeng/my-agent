#!/usr/bin/env bash
# build.sh — 构建 my-agent 桌面界面（Flutter / Linux release）
#   FLUTTER_HOME 可覆盖（默认 ~/development/flutter）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FLUTTER="${FLUTTER_HOME:-$HOME/development/flutter}/bin/flutter"
[ -x "$FLUTTER" ] || { echo "未找到 Flutter SDK: $FLUTTER" >&2; exit 1; }
cd "$HERE"
echo "[1/2] flutter pub get ..."; "$FLUTTER" pub get
echo "[2/2] flutter build linux --release ..."; "$FLUTTER" build linux --release
echo "完成：$HERE/build/linux/x64/release/bundle/myagent_ui"
