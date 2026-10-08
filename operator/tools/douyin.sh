#!/usr/bin/env bash
# tools/douyin.sh — 抖音「我的作品」下载：取文案/标签，视频存本地，高赞转 wav 做克隆音色
# 原理：CDP 从已登录 Chrome 拿登录 cookie + 作品列表(接口 aweme/v1/web/aweme/post) → curl 下视频。
# @desc 抖音作品：前 N 条下载到 ~/douyin/<uid> （文案/标签/视频；高赞转 wav 供克隆）；默认抓自己，可指定 uid
# @usage tools/douyin.sh list [N] [<主页URL>|--uid <sec_uid>|--url <主页URL>]                 # 列前 N 条(id/赞/文案/标签)
#        tools/douyin.sh get  [N] [--min-like 30] [<主页URL>|--uid <sec_uid>|--url <主页URL>] # 下载前 N 条+文案/标签+高赞wav
# @rule **抖音作品/文案/音色**：说“抓我抖音前N条作品 / 下载 <某人> 的抖音 / 要抖音文案标签”→ `tools/douyin.sh get <N>`（默认18，抓自己）。**用户直接发主页 URL（或分享短链）也可以**：`tools/douyin.sh get <N> "<url>"`（也支持 `--uid <sec_uid>`/`--url <url>`，短链会自动解析）。会下载视频到 `~/douyin/<uid>/`、生成 `文案.txt`/`标签.txt`（标签可用于发布参考），并把**点赞≥阈值(默认30)**的转成 16k wav 存 `wav/`（可 `tools/voices.sh add <名> <wav>` 克隆音色）。只看不下载用 `list <N>`。**前提：Chrome 已登录抖音且开着调试口 9222。** 默认不发微信。
# @order 14
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36'

CMD="${1:-list}"; shift || true
N=18; MINLIKE=30; SEC=""
# 从主页 URL / 短链解析 sec_uid
extract_sec() {
  local u="$1" sec
  sec="$(printf '%s' "$u" | sed -nE 's#.*/user/([^/?]+).*#\1#p')"
  [ -n "$sec" ] && { printf '%s' "$sec"; return; }
  local final
  final="$(curl -sIL --max-time 20 -A "$UA" "$u" 2>/dev/null | sed -nE 's#^[Ll]ocation: *([^ ]+).*#\1#p' | tail -1)"
  printf '%s' "$final" | sed -nE 's#.*/user/([^/?]+).*#\1#p'
}
while [ $# -gt 0 ]; do
  case "$1" in
    --min-like) MINLIKE="${2:-30}"; shift 2 ;;
    --uid) SEC="${2:-}"; shift 2 ;;
    --url) SEC="$(extract_sec "${2:-}")"; shift 2 ;;
    https://*|http://*) SEC="$(extract_sec "$1")"; shift ;;
    [0-9]*) N="$1"; shift ;;
    *) shift ;;
  esac
done
D=""
COOK="$HOME/.myagent_douyin_cookie"

# 1) 取 cookie + 列表
if ! out="$(node "$DIR/douyin_fetch.js" "$N" "$SEC" 2>&1)"; then
  echo "$out" >&2
  echo "抖音取数失败：确认 Chrome 已登录抖音、且开着远程调试(9222)。" >&2
  exit 1
fi
echo "$out"
[ -s /tmp/douyin_list.json ] || { echo "未取到作品列表" >&2; exit 1; }
# 保存目录：自己 → ~/douyin/base ；指定用户 → ~/douyin/<uid>/
if [ -n "$SEC" ]; then D="${DOUYIN_DIR:-$HOME/douyin}/$SEC"; else D="${DOUYIN_DIR:-$HOME/douyin}/base"; fi
mkdir -p "$D/video" "$D/wav"

# 2) 文案 / 标签（用 jq，避免字段错位）
jq -r '.[] | ((.i)|tostring)+" | 赞"+((.digg)|tostring)+" | "+(.desc|gsub("#[^# ]+";"")|gsub("[ \t\n\r]+";" ")|sub("^ +";"")|sub(" +$";""))' /tmp/douyin_list.json > "$D/文案.txt"
jq -r '.[] | ((.i)|tostring)+" | "+([.desc|scan("#[^# ]+")]|join(" "))' /tmp/douyin_list.json > "$D/标签.txt"

if [ "$CMD" = "list" ]; then
  paste -d'	' <(cut -d'|' -f1-3 "$D/文案.txt") <(cut -d'|' -f2- "$D/标签.txt" | sed 's/^/标签: /')
  echo "（list 模式，未下载；下载用: douyin.sh get $N）"
  exit 0
fi

# 3) get：下载视频；高赞转 wav
echo "下载到 $D/video ..."
n=0
while IFS=$'\t' read -r i id digg url; do
  [ -z "$id" ] && continue
  f="$D/video/$(printf '%02d' "$i")_${id}.mp4"
  if [ ! -s "$f" ]; then
    curl -sL --max-time 180 -e 'https://www.douyin.com/' -A "$UA" -b "$COOK" -o "$f" "$url" </dev/null
  fi
  if [ -s "$f" ]; then
    n=$((n+1))
    if [ "${digg:-0}" -ge "$MINLIKE" ]; then
      ffmpeg -y -i "$f" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$D/wav/${id}.wav" </dev/null >/dev/null 2>&1 && echo "  wav: 第${i}条 赞${digg} → ${id}.wav"
    fi
  else
    echo "  第${i}条 下载失败" >&2
  fi
done < <(jq -r '.[] | [.i,.id,.digg,.url]|@tsv' /tmp/douyin_list.json)
echo "完成：视频 $n/$N → $D/video/  文案/标签 → $D/文案.txt,标签.txt  高赞wav → $D/wav/"
