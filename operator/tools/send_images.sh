#!/usr/bin/env bash
# tools/send_images.sh — 下载图片（微博/新浪小图自动换大图），保存到目录或发微信（LuaJIT 实现）
# @desc 下载图片（小图自动换大图）：保存目录并报张数，或发微信
# @usage tools/send_images.sh [--save 目录] [--to 会话] [--each] [--limit N] <图片URL...>   （URL 也可从 stdin 每行一个）
# @rule **下载图片URL**：当你已拿到图片 URL（来自网页/接口）→ `tools/send_images.sh --save <目录> <url...>`（自动把 /orj360//thumb150//mw690/ 等**小图换成 /large/ 大图**后下载并保存，报告张数）。加 `--to 会话` 才发微信。看某明星微博图请用 `weibo_imgs.sh`。
# @order 21
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/send_images.lua" "$@"
