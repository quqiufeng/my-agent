#!/usr/bin/env bash
# tools/note.sh — 备忘 / 待办（存 ~/.myagent_notes，纯文本，LuaJIT 实现）
# @rule **备忘/待办**：说“记一下…/备忘…/待办…”→ `note.sh add "…"`；“有什么待办/列出备忘”→ `note.sh list`；“完成第 N 条/删第 N 条”→ `note.sh done N`；“清空”→ `clear`。
# @order 12
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/note.lua" "$@"
