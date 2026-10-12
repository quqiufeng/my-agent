#!/usr/bin/env bash
# tools/fetch.sh — 通用带 cookie 抓取（curl，不需要浏览器）
# @desc 用 curl 抓取网页/接口，可带 ~/.env 里的 cookie（登录态）
# @usage tools/fetch.sh <url> [--cookie ENVKEY] [--post DATA] [--json] [--save FILE] [--referer URL] [--header 'K: V'] [--ua UA]
# @rule **登录态抓取**（微博/知乎/某站资料）→ `tools/fetch.sh <url> --cookie <ENVKEY>`（cookie 先用 `cookie.sh save` 落盘）；**不要**为此开浏览器或 OCR 网页。
# @order 42
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
url=""; ckkey=""; post=""; save=""; json=0; ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36"; referer=""
extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    --cookie)  ckkey="${2:-}";   shift 2 ;;
    --post)    post="${2:-}";    shift 2 ;;
    --save)    save="${2:-}";    shift 2 ;;
    --referer) referer="${2:-}"; shift 2 ;;
    --header)  extra+=(-H "${2:-}"); shift 2 ;;
    --ua)      ua="${2:-}";      shift 2 ;;
    --json)    json=1;           shift ;;
    *) [ -z "$url" ] && url="$1"; shift ;;
  esac
done
[ -n "$url" ] || { echo "用法: fetch.sh <url> [--cookie ENVKEY] [--post DATA] [--json] [--save FILE] [--referer URL] [--header 'K: V']" >&2; exit 2; }

args=(-sSL --max-time 30 -A "$ua")
[ -n "$referer" ] && args+=(-e "$referer")
if [ -n "$ckkey" ]; then
  ck="$(bash "$DIR/cookie.sh" get "$ckkey")"
  [ -n "$ck" ] || { echo "无 cookie: $ckkey（先 cookie.sh save <域名> $ckkey）" >&2; exit 3; }
  args+=(-H "Cookie: $ck")
fi
if [ -n "$post" ]; then
  [ "$json" = 1 ] && args+=(-H "Content-Type: application/json")
  args+=(--data "$post")
fi
if [ "${#extra[@]}" -gt 0 ]; then args+=("${extra[@]}"); fi

if [ -n "$save" ]; then curl "${args[@]}" -o "$save" "$url" && echo "$save"; else curl "${args[@]}" "$url"; fi
