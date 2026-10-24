#!/usr/bin/env bash
# tools/find_file.sh — 按文件名关键词搜索本机文件 + WebDAV，返回匹配（本地路径 或 可下载 URL，LuaJIT 实现）
# @rule **发文件给我**：说“把 xxx 文件发我 / 找 xxx 文件 / 发我某首歌 / 找某部美剧”→ 先 `find_file.sh <关键词>`（本机 + WebDAV 都搜）。唯一匹配就直接 `wechat_send_file.sh <路径或URL>`；多个匹配先把候选列给用户确认，不要盲发。
# @order 9
# 用法: find_file.sh <关键词> [数量=15]
# 本地范围: $HOME、/tmp、/data（跳过噪声目录）
# WebDAV 范围: $WEBDAV_SEARCH（冒号分隔，默认 $WEBDAV_MUSIC）
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/find_file.lua" "$@"
