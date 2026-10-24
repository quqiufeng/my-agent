#!/usr/bin/env bash
# tools/weibo_album.sh — 微博「相册」大图下载（LuaJIT 实现）
# @desc 微博相册大图下载（搜昵称定 uid → 相册接口翻页取大图 → 存 ~ 报张数）
# @usage tools/weibo_album.sh <昵称|uid> [页数 | all，默认 20] [--save 目录] [--to 会话] [--limit N]
# @rule **下载某人的微博相册（全量大图）**：说“下载 <某人> 的微博相册 / 抓 <某人> 相册的图 / <某人> 相册”→ `tools/weibo_album.sh <昵称>`。先按昵称搜出 uid（也可直接给数字 uid），再用相册接口翻页取**大图**（比搜索页快很多），存到 ~ 下的目录并报张数（默认不发微信；说“发我”才加 `--to`）。
# @order 21
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/weibo_album.lua" "$@"
