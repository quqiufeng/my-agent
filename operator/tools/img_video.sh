#!/usr/bin/env bash
# tools/img_video.sh — 提示词生成图片并转成 MP4（LuaJIT 编排）
# @desc 动画/图片视频：按提示词出图，再合成竖版 MP4（默认 1080×1920，不发微信）
# @usage tools/img_video.sh --scenes "提示词1|提示词2|…" [--out out.mp4] [--img-preset xhs|pyq] [--seconds N] [--send [--to 会话]] [--fg]
#        tools/img_video.sh --imgdir <图片目录> [--out out.mp4] [--seconds N] [--send [--to 会话]] [--fg]
# @rule **做图片视频/动画短片**：说“用<提示词/故事>生成图片视频 / 做动画短片 / 把这几张图做成视频”→ `tools/img_video.sh --scenes "<提示词1|提示词2>"`；已有图片用 `--imgdir <目录>`。默认后台跑，完成后文件在 `~/image/`；要发微信加 `--send [--to 会话]`。
# @order 16
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/img_video.lua" "$@"
