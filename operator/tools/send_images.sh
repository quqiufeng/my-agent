#!/usr/bin/env bash
# tools/send_images.sh — 下载图片（微博/新浪小图自动换大图），保存到目录或发微信
# @desc 下载图片（小图自动换大图）：保存目录并报张数，或发微信
# @usage tools/send_images.sh [--save 目录] [--to 会话] [--each] [--limit N] <图片URL...>   （URL 也可从 stdin 每行一个）
# @rule **下载图片URL**：当你已拿到图片 URL（来自网页/接口）→ `tools/send_images.sh --save <目录> <url...>`（自动把 /orj360//thumb150//mw690/ 等**小图换成 /large/ 大图**后下载并保存，报告张数）。加 `--to 会话` 才发微信。看某明星微博图请用 `weibo_imgs.sh`。
# @order 21
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

TO=""; EACH=0; LIMIT=0; SAVE=""
URLS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --to)    TO="${2:-}"; shift 2 ;;
        --save)  SAVE="${2:-}"; shift 2 ;;
        --each)  EACH=1; shift ;;
        --limit) LIMIT="${2:-0}"; shift 2 ;;
        *)       URLS+=("$1"); shift ;;
    esac
done
if [ ! -t 0 ]; then while IFS= read -r l; do [ -n "$l" ] && URLS+=("$l"); done; fi
[ "${#URLS[@]}" -eq 0 ] && { echo "用法: send_images.sh [--save 目录] [--to 会话] [--each] [--limit N] <图片URL...>" >&2; exit 2; }

# 小图 → 大图（微博/新浪 CDN）
tidy() { printf '%s' "$1" | sed -E 's#/(orj360|orj480|thumb150|thumb180|thumbnail|mw690|small|wap360|bmiddle)/#/large/#g'; }

D="/tmp/myagent_imgs_$(date +%s)"; mkdir -p "$D"
: > "$D/urls"
i=0
for u in "${URLS[@]}"; do
    i=$((i+1)); [ "$LIMIT" -gt 0 ] && [ "$i" -gt "$LIMIT" ] && break
    printf '%05d %s\n' "$i" "$(tidy "$u")" >> "$D/urls"
done
export D
# 并行下载（8 并发）；下不到就换尺寸重试 large↔mw690↔orj360，解决部分图 /large/ 404
xargs -a "$D/urls" -P 8 -n 2 sh -c '
  out="$D/$1.jpg"; u="$2"
  curl -sL --max-time 40 -A "Mozilla/5.0" -H "Referer: https://weibo.com/" -o "$out" "$u" 2>/dev/null
  if [ ! -s "$out" ]; then
    for s in mw690 large orj360 thumb150; do
      v="$(printf "%s" "$u" | sed -E "s#/(large|mw690|orj360|thumb150|thumb180|orj480|thumbnail|small|wap360|bmiddle)/#/$s/#")"
      curl -sL --max-time 40 -A "Mozilla/5.0" -H "Referer: https://weibo.com/" -o "$out" "$v" 2>/dev/null
      [ -s "$out" ] && break
    done
  fi
' _

FILES=()
for f in "$D"/[0-9]*.jpg; do
    [ -f "$f" ] || continue
    if [ -s "$f" ] && identify "$f" >/dev/null 2>&1; then FILES+=("$f"); else rm -f "$f"; fi
done
[ "${#FILES[@]}" -eq 0 ] && { echo "没下到图片（URL 可能失效）" >&2; exit 1; }

# 保存模式：不下微信，移到指定目录，报张数
if [ -n "$SAVE" ]; then
    mkdir -p "$SAVE" 2>/dev/null
    n=0
    for f in "${FILES[@]}"; do
        n=$((n+1))
        cp -f "$f" "$SAVE/$(printf '%s%03d.jpg' "${SAVE_PREFIX:-}" "$n")" 2>/dev/null
    done
    rm -rf "$D"
    echo "已保存 ${#FILES[@]} 张到 $SAVE"
    exit 0
fi

echo "下载 ${#FILES[@]} 张大图"
if [ "$EACH" = "1" ]; then
    for f in "${FILES[@]}"; do
        if [ -n "$TO" ]; then "$DIR/wechat_send_file.sh" "$f" --to "$TO" >/dev/null 2>&1
        else "$DIR/wechat_send_file.sh" "$f" >/dev/null 2>&1; fi
    done
    echo "已发 ${#FILES[@]} 张 -> ${TO:-文件传输助手}"
else
    SHEET="$D/sheet.jpg"
    if [ "${#FILES[@]}" -eq 1 ]; then cp "${FILES[0]}" "$SHEET"
    else montage "${FILES[@]}" -tile 3x -geometry 520x520+6+6 -background '#ffffff' "$SHEET" 2>/dev/null || cp "${FILES[0]}" "$SHEET"; fi
    if [ -n "$TO" ]; then "$DIR/wechat_send_file.sh" "$SHEET" --to "$TO"; else "$DIR/wechat_send_file.sh" "$SHEET"; fi
    echo "已发拼图(${#FILES[@]}张) -> ${TO:-文件传输助手}"
fi
