#!/usr/bin/env bash
# tools/douyin.sh — 抖音「我的作品」下载（LuaJIT 实现）
# 原理：CDP 从已登录 Chrome 拿登录 cookie + 作品列表 → curl 下视频。
# @desc 抖音作品：前 N 条下载到 ~/douyin/<uid> （文案/标签/视频；高赞转 wav 供克隆）；默认抓自己，可指定 uid
# @usage tools/douyin.sh list [N] [<主页URL>|--uid <sec_uid>|--url <主页URL>]                 # 列前 N 条(id/赞/文案/标签)
#        tools/douyin.sh get  [N] [--min-like 30] [<主页URL>|--uid <sec_uid>|--url <主页URL>] # 下载前 N 条+文案/标签+高赞wav
# @rule **抖音作品/文案/音色**：说“抓我抖音前N条作品 / 下载 <某人> 的抖音 / 要抖音文案标签”→ `tools/douyin.sh get <N>`（默认18，抓自己）。**用户直接发主页 URL（或分享短链）也可以**：`tools/douyin.sh get <N> "<url>"`（也支持 `--uid <sec_uid>`/`--url <url>`，短链会自动解析）。会下载视频到 `~/douyin/<uid>/`、生成 `文案.txt`/`标签.txt`（标签可用于发布参考），并把**点赞≥阈值(默认30)**的转成 16k wav 存 `wav/`（可 `tools/voices.sh add <名> <wav>` 克隆音色）。只看不下载用 `list <N>`。**前提：Chrome 已登录抖音且开着调试口 9222。** 默认不发微信。
# @order 14
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/douyin.lua" "$@"
