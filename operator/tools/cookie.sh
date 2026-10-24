#!/usr/bin/env bash
# tools/cookie.sh — 管理 ~/.env 里的 <ENVKEY>_COOKIE（供带登录态抓取，LuaJIT 实现）
# @desc 把某站点 cookie 从已登录 Chrome(CDP) 取出并存入 ~/.env，或直接读写
# @usage tools/cookie.sh save <域名> <ENVKEY> | set <ENVKEY> <值> | get <ENVKEY> | list
# @rule 需要**登录态抓取**时：先 `tools/cookie.sh save <域名> <ENVKEY>`（从已登录 Chrome 取 cookie 落到 ~/.env），再用 `tools/fetch.sh <url> --cookie <ENVKEY>`；不要为此开浏览器。
# @order 41
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/cookie.lua" "$@"
