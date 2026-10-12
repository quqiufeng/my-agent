#!/usr/bin/env bash
# tools/cookie.sh — 管理 ~/.env 里的 <ENVKEY>_COOKIE（供带登录态抓取）
# @desc 把某站点 cookie 从已登录 Chrome(CDP) 取出并存入 ~/.env，或直接读写
# @usage tools/cookie.sh save <域名> <ENVKEY> | set <ENVKEY> <值> | get <ENVKEY> | list
# @rule 需要**登录态抓取**时：先 `tools/cookie.sh save <域名> <ENVKEY>`（从已登录 Chrome 取 cookie 落到 ~/.env），再用 `tools/fetch.sh <url> --cookie <ENVKEY>`；不要为此开浏览器。
# @order 41
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ENVF="${ENVF:-$HOME/.env}"

setkey() { # key value
    local key="$1" val="$2" tmp esc
    tmp="$(mktemp)"; [ -f "$ENVF" ] && grep -v "^${key}=" "$ENVF" > "$tmp" 2>/dev/null || true
    esc="${val//\'/\'\\\'\'}"                 # 转义单引号
    printf "%s='%s'\n" "$key" "$esc" >> "$tmp"
    mv "$tmp" "$ENVF"
}
getkey() { grep "^$1=" "$ENVF" 2>/dev/null | head -1 | sed "s/^$1=//; s/^'//; s/'$//"; }

cmd="${1:-}"
case "$cmd" in
  save)
    host="${2:?用法: cookie.sh save <域名> <ENVKEY>}"; key="${3:?缺 ENVKEY}"
    v="$(node "$DIR/cookies.js" "$host")"
    [ -n "$v" ] || { echo "未从 Chrome 取到 cookie（确认已登录且 Chrome 在跑）" >&2; exit 1; }
    setkey "$key" "$v"
    echo "已保存 $key（$(( $(printf '%s' "$v" | tr ';' '\n' | grep -c '=') )) 项）→ $ENVF"
    ;;
  set) shift; key="${1:?缺 ENVKEY}"; shift; setkey "$key" "$*"; echo "已写入 $key" ;;
  get) getkey "${2:?缺 ENVKEY}" ;;
  list) grep -oE '^[A-Z0-9_]+_COOKIE' "$ENVF" 2>/dev/null ;;
  *) echo "用法: cookie.sh save <域名> <ENVKEY> | set <ENVKEY> <值> | get <ENVKEY> | list" >&2; exit 2 ;;
esac
