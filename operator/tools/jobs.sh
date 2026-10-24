#!/usr/bin/env bash
# tools/jobs.sh — 查看/停止后台长任务（日志式进度）
# @desc 后台任务：列出、看日志尾部、停止、查状态
# @usage tools/jobs.sh list | tail <id> [行数] | stop <id> | status <id>
# @rule 长任务返回 `job=<id>` 后，用 `tools/jobs.sh tail <id>` 看进度/结果；`list` 看全部；`stop <id>` 停止。
# @order 53
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/jobs.lua" "$@"
