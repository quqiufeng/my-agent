#!/usr/bin/env bash
# tools/sale_points.sh — 读取「带货引流视频」资料包（说明 + 卖点，LuaJIT 实现）
# @desc 读取带货引流视频资料包（规则说明 + 卖点）
# @usage tools/sale_points.sh
# @rule **做带货引流视频文案前，先跑 `tools/sale_points.sh`** 读取资料包（规则+卖点），再严格按其中规则写文案，然后用 `tools/video_dub.sh` 出片。
# @order 13
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/sale_points.lua" "$@"
