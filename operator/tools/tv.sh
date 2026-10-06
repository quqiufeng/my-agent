#!/usr/bin/env bash
# tools/tv.sh — DAV 美剧/电影：列出 / 播放 / 下一集 / 停止（VLC 播放，默认本机屏幕）
# 用法:
#   tv.sh list                  # 列出所有剧
#   tv.sh list <剧名>            # 列出某剧的季/集
#   tv.sh play <剧名> [季] [集]  # 播放（省略季/集=第一季第一集；季/集可用序号或 s1/S01/数字）
#   tv.sh next                  # 下一集
#   tv.sh stop                  # 停止
# 搜索/播放根目录用 ~/.env 的 WEBDAV_SEARCH（默认 WEBDAV_MUSIC）。
set -uo pipefail
[ -f "$HOME/.env" ] && { set -a; . "$HOME/.env"; set +a; }
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
url="${WEBDAV_URL:-}"; U="${WEBDAV_USER:-}"; P="${WEBDAV_PASS:-}"
ROOTS="${WEBDAV_SEARCH:-${WEBDAV_MUSIC:-}}"
PIDF=/tmp/myagent_tv.pid; NOW=/tmp/myagent_tv_now; STATE=/tmp/myagent_tv_state
LOGF=/tmp/myagent_tv.log
[ -n "$url" ] || { echo "未配置 WEBDAV_URL" >&2; exit 1; }

pf()   { curl -sS -m 25 -u "$U:$P" -X PROPFIND -H 'Depth: 1' "$url$1" 2>/dev/null | grep -oP '(?<=<[Dd]:href>)[^<]+'; }
dec()  { printf '%b' "${1//%/\\x}"; }
name() { local b="${1%/}"; dec "${b##*/}"; }
urlenc(){ local s="$1" o="" c h i; for ((i=0;i<${#s};i++)); do c="${s:i:1}"; case "$c" in [a-zA-Z0-9.~_-]) o+="$c";; *) printf -v h '%%%02X' "'$c"; o+="$h";; esac; done; printf '%s' "$o"; }

show_of() { # 关键词 -> show href
  local kw="$1" href
  local IFS=':'; local -a dr; read -r -a dr <<< "$ROOTS"
  for root in "${dr[@]}"; do
    [ -z "$root" ] && continue
    while IFS= read -r href; do
      [ "$href" = "$root/" ] && continue
      case "$href" in
        */) if name "$href" | grep -qiF -- "$kw"; then echo "$href"; return 0; fi ;;
      esac
    done < <(pf "$root/")
  done
  return 1
}

list_shows() {
  local href
  local IFS=':'; local -a dr; read -r -a dr <<< "$ROOTS"
  for root in "${dr[@]}"; do
    [ -z "$root" ] && continue
    while IFS= read -r href; do
      case "$href" in
        */) [ "$href" = "$root/" ] && continue
            n="$(name "$href")"
            case "$n" in .*|mp3|book|av|无损音源|亚马逊原版电子书|手机备份) continue;; esac
            echo "$n" ;;
      esac
    done < <(pf "$root/")
  done
}

# 列出某 href 下的子目录/文件（排序）
children() { local p="$1"; pf "$p" | while read -r h; do [ "$h" = "${p%/}/" ] && continue; echo "$h"; done | sort; }
subdirs()  { children "$1" | while read -r h; do case "$h" in */) echo "$h";; esac; done; }
files()    { children "$1" | while read -r h; do case "$h" in */) ;; *) echo "$h";; esac; done; }

# 选季：arg 为空取第 1 个；(arg=s1|S01|1 -> 匹配或第 arg 个)
pick_season() {
  local show="$1" arg="$2" i=0 h
  while IFS= read -r h; do
    i=$((i+1))
    if [ -z "$arg" ]; then [ "$i" -eq 1 ] && { echo "$h"; return 0; }
    elif name "$h" | grep -qiF -- "$arg" || [ "$i" -eq "${arg:-0}" ] 2>/dev/null; then echo "$h"; return 0
    fi
  done < <(subdirs "$show")
  return 1
}
# 选集：arg 为空取第 1 个；数字取第 N 个
pick_ep() {
  local dir="$1" arg="$2" i=0 h
  while IFS= read -r h; do
    i=$((i+1))
    [ -z "$arg" ] && { echo "$h"; return 0; }
    [ "$i" -eq "$arg" ] 2>/dev/null && { echo "$h"; return 0; }
  done < <(files "$dir")
  return 1
}

stop() { [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null; pkill -x vlc 2>/dev/null; rm -f "$PIDF"; }

play_file() { # $1 = episode href
  local ep="$1" host="${url#http://}"; host="${host#https://}"
  stop
  setsid vlc --intf qt --no-video-title-show \
    "http://$(urlenc "$U"):$(urlenc "$P")@${host}${ep}" \
    </dev/null >"$LOGF" 2>&1 &
  echo $! > "$PIDF"
  name "$ep" > "$NOW"
  echo "正在播放: $(name "$ep")"
}

cmd="${1:-}"; shift || true

case "$cmd" in
  list)
    kw="${1:-}"
    if [ -z "$kw" ]; then list_shows; exit 0; fi
    show="$(show_of "$kw")" || { echo "没找到剧: $kw"; exit 1; }
    echo "== $(name "$show") =="
    seasons=(); while IFS= read -r s; do seasons+=("$s"); done < <(subdirs "$show")
    if [ "${#seasons[@]}" -gt 0 ]; then
      for s in "${seasons[@]}"; do
        echo "[$(name "$s")]"
        files "$s" | while read -r f; do echo "   $(name "$f")"; done
      done
    else
      files "$show" | while read -r f; do echo "  $(name "$f")"; done
    fi
    ;;

  play)
    kw="${1:-}"; season="${2:-}"; ep="${3:-}"
    [ -z "$kw" ] && { echo "用法: tv.sh play <剧名> [季] [集]" >&2; exit 2; }
    show="$(show_of "$kw")" || { echo "没找到剧: $kw"; exit 1; }
    if subdirs "$show" | grep -q .; then
      sd="$(pick_season "$show" "$season")" || { echo "没找到季"; exit 1; }
    else
      sd="$show/"; season=""
    fi
    epf="$(pick_ep "$sd" "$ep")" || { echo "没找到集"; exit 1; }
    printf 'SHOW=%s\nSEASON=%s\n' "$show" "$sd" > "$STATE"
    play_file "$epf"
    ;;

  next)
    [ -f "$STATE" ] || { echo "还没在播（先 play）"; exit 1; }
    . "$STATE" 2>/dev/null || true
    cur="$(cat "$NOW" 2>/dev/null || true)"
    next=""; hit=0
    while IFS= read -r f; do
      if [ "$hit" = "1" ]; then next="$f"; break; fi
      [ "$(name "$f")" = "$cur" ] && hit=1
    done < <(files "$SEASON")
    [ -z "$next" ] && { echo "已经是最后一集"; exit 0; }
    play_file "$next"
    ;;

  stop) stop; echo "已停止播放" ;;
  *) echo "用法: tv.sh list [剧名] | play <剧名> [季] [集] | next | stop" ;;
esac
