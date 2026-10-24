#!/usr/bin/env bash
# tools/dev.sh — 自我开发：项目结构/规范 + 新建「网页能力」工具（LuaJIT 实现）
# @desc 本项目结构与规范；新能力=一个**走专用 Chrome(免授权登录)+CDP/DOM 的网页工具**（能力来自网页，安全）；支持新建/索引/提交(可回滚)/重启
# @usage tools/dev.sh info | caps | list | new <name> | index | commit [msg] | push | restart
# @rule **需求现有工具满足不了时**：`tools/dev.sh info` 读规范 → `tools/dev.sh new <name>` 生成网页工具模板（里层用专用 Chrome + `ak.cdp` 做 DOM 操作）→ 填逻辑 → `commit`（可回滚）→ `restart` 生效。**能力只来自网页（免授权 Chrome + CDP/DOM）**，不写碰本机任意资源的脚本，也不做浏览器扩展。
# @order 1
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/dev.lua" "$@"
