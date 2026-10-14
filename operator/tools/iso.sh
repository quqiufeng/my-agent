#!/usr/bin/env bash
# tools/iso.sh — 用 anatomy(等距插画 kit) 出图/出动画 → 发微信
# @desc 等距解释图：kit→SVG→解析CSS变量→resvg 出 PNG（快，免浏览器）；`--page` 出整页卡片(Chrome)；`anim` 逐帧出 GIF/MP4（动画）
# @usage tools/iso.sh render <build.mjs|example名> [--theme dark|light] [--page] [--out 目录] [--to 会话] [--no-send] [--zoom N]
# @usage tools/iso.sh anim   <build.mjs> [--frames N] [--theme ..] [--out 目录] [--to 会话] [--no-send]
# @rule **画等距图/动画**：按 `operator/tools/iso/anatomy/references/{craft,kit,motion}.md` 的 craft 写 `build.mjs`（用 `kit/iso-kit.mjs` 造零件；动画读环境 `ISO_FRAME/ISO_N` 逐帧重建运动件）。出图 `tools/iso.sh render <build.mjs>`；动画 `tools/iso.sh anim <build.mjs>`；也可 `render <样例名>`。
# @order 30
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
KIT="${ANATOMY_DIR:-$DIR/iso/anatomy}"   # 我们目录里的 kit（自包含；不引用 /opt/anatomy）
RESVG="${RESVG:-$HOME/.local/bin/resvg}"
FF="$(command -v ffmpeg || true)"

usage(){ echo "用法: iso.sh render <build.mjs|样例> [--theme dark|light] [--page] [--out 目录] [--to 会话] [--no-send] [--zoom N]" >&2
         echo "      iso.sh anim   <build.mjs> [--frames N] [--theme ..] [--out 目录] [--to 会话] [--no-send]" >&2; exit 2; }
CMD="${1:-render}"; shift; case "$CMD" in render|anim) ;; *) usage ;; esac

SRC=""; OUTD="/tmp/opencode"; TO=""; SEND=1; ZOOM=2; THEME="light"; PAGE=0; FRAMES=48
while [ $# -gt 0 ]; do case "$1" in
  --out) OUTD="$2"; shift 2 ;; --to) TO="$2"; shift 2 ;; --theme) THEME="$2"; shift 2 ;;
  --zoom) ZOOM="$2"; shift 2 ;; --frames) FRAMES="$2"; shift 2 ;; --page) PAGE=1; shift ;; --no-send) SEND=0; shift ;;
  -*) shift ;; *) [ -z "$SRC" ] && SRC="$1"; shift ;;
esac; done
[ -n "$SRC" ] || usage

if [ -d "$KIT/examples/$SRC" ]; then BM="$KIT/examples/$SRC/build.mjs"
elif [ -f "$SRC" ]; then BM="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
else echo "找不到 build.mjs: $SRC" >&2; exit 1; fi
command -v node >/dev/null || { echo "需要 node" >&2; exit 1; }
WD="$(cd "$(dirname "$BM")" && pwd)"; NAME="$(basename "$WD")"
mkdir -p "$OUTD"
BG="#f4f3ef"; [ "$THEME" = "dark" ] && BG="#131313"
send() { if [ -n "$TO" ]; then "$DIR/wechat_send_file.sh" "$1" --to "$TO" >/dev/null 2>&1; else "$DIR/wechat_send_file.sh" "$1" >/dev/null 2>&1; fi; echo "已发送 -> ${TO:-文件传输助手}"; }
resolve(){ python3 - "$1" "$2" <<'PY'
import re,sys
svg=open(sys.argv[1]).read(); v={}
for m in re.finditer(r'--([A-Za-z0-9-]+)\s*:\s*([^;{}]+)', svg): v[m.group(1)]=m.group(2).strip()
for _ in range(12):
    s2=re.sub(r'var\(--([A-Za-z0-9-]+)\)', lambda m:v.get(m.group(1),m.group(0)), svg)
    if s2==svg: break
    svg=s2
open(sys.argv[2],"w").write(svg)
PY
}
prep_standalone(){ cp "$BM" "$WD/.iso_build.mjs"
  sed -i "0,/figureSvg({/s//figureSvg({ standalone: \"$THEME\",/" "$WD/.iso_build.mjs"
  echo 'try{writeFileSync(new URL("./.iso_out.svg", import.meta.url), svg);}catch(e){console.error("no svg: "+e.message)}' >> "$WD/.iso_build.mjs"; }

if [ "$CMD" = "anim" ]; then
  [ -x "$RESVG" ] || { echo "缺 resvg" >&2; exit 1; }
  [ -n "$FF" ] || { echo "缺 ffmpeg" >&2; exit 1; }
  prep_standalone
  FD="$OUTD/${NAME}_frames"; rm -rf "$FD"; mkdir -p "$FD"
  for i in $(seq 0 $((FRAMES-1))); do
    ( cd "$WD" && ISO_FRAME=$i ISO_N=$FRAMES node .iso_build.mjs >/dev/null 2>&1 )
    [ -f "$WD/.iso_out.svg" ] || { echo "第 $i 帧没出 SVG" >&2; exit 1; }
    resolve "$WD/.iso_out.svg" "$WD/.iso_fixed.svg"
    "$RESVG" --zoom "$ZOOM" --background "$BG" "$WD/.iso_fixed.svg" "$(printf '%s/f%03d.png' "$FD" "$i")" 2>/dev/null
  done
  GIF="$OUTD/${NAME}_iso.gif"; MP4="$OUTD/${NAME}_iso.mp4"
  "$FF" -y -loglevel error -framerate 20 -i "$FD/f%03d.png" -pix_fmt yuv420p "$MP4"
  "$FF" -y -loglevel error -framerate 20 -i "$FD/f%03d.png" -vf "scale=560:-1,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "$GIF"
  echo "动画: $GIF ($(du -h "$GIF"|cut -f1)) 帧=$FRAMES"
  [ "$SEND" = "1" ] && send "$GIF"
  exit 0
fi

# render
PNG="$OUTD/${NAME}_iso.png"
if [ "$PAGE" = "1" ]; then
  BARGS=(); [ "$THEME" = "light" ] && BARGS=(--light)
  HTML="$( cd "$WD" && node "$(basename "$BM")" "${BARGS[@]}" 2>/dev/null | sed -n 's/^wrote //p' | head -1 )"
  [ -f "$WD/$HTML" ] || HTML="$(ls -t "$WD"/*light.html "$WD"/*.html 2>/dev/null | head -1 | xargs -r basename)"
  [ -f "$WD/$HTML" ] || { echo "没找到生成的 .html" >&2; exit 1; }
  ( cd "$WD" && node "$KIT/scripts/capture.mjs" "$HTML" --out "$PNG" 2>&1 | tail -1 )
else
  [ -x "$RESVG" ] || { echo "缺 resvg" >&2; exit 1; }
  prep_standalone
  ( cd "$WD" && node .iso_build.mjs >/dev/null 2>&1 )
  [ -f "$WD/.iso_out.svg" ] || { echo "生成 SVG 失败（可加 --page）" >&2; exit 1; }
  resolve "$WD/.iso_out.svg" "$WD/.iso_fixed.svg"
  "$RESVG" --zoom "$ZOOM" --background "$BG" "$WD/.iso_fixed.svg" "$PNG" 2>/dev/null || "$RESVG" "$WD/.iso_fixed.svg" "$PNG" 2>/dev/null
fi
[ -s "$PNG" ] || { echo "渲染失败" >&2; exit 1; }
echo "出图: $PNG ($(identify -format '%wx%h' "$PNG" 2>/dev/null))"
[ "$SEND" = "1" ] && send "$PNG"
