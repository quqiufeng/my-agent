#!/usr/bin/env bash
# tools/weibo_imgs.sh — 看某明星微博图：用微博 cookie curl 搜索页，抓图 → 小图换大图 → 保存/发微信（LuaJIT 实现）
# @desc 下载微博图（打开微博搜索，抓九宫格图并小图换大图，直接存到 ~ 报张数）
# @usage tools/weibo_imgs.sh <明星/关键词> [页数 | A-B | all，默认 20] [--save 目录] [--each] [--limit N] [--to 会话] [--refresh-cookie]
# @rule **下载微博图**：说“下载微博图 <明星> / 抓 <明星> 的微博图 / 找 <明星> 的图”→ `tools/weibo_imgs.sh <明星>`。**默认抓 1..20 页**（也可 `N`、`A-B` 或 `all`）。用**微博 cookie（存在 ~/.env，长期免授权）** curl 抓 `s.weibo.com` 搜索页，解析帖子图片并自动把小图换成大图，**直接保存到 ~ 下的目录**并报告下载张数（默认不发微信）。只有用户明确说“发我微信/发过来”才加 `--to` 发送，**发送时也保留本地图片**；cookie 过期（抓不到）时才用 `--refresh-cookie` 从已登录 Chrome 重取一次。
# @order 20
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/weibo_imgs.lua" "$@"
