#!/usr/bin/env bash
# tools/photo.sh — USB 摄像头拍照并发微信（LuaJIT 实现）
# @rule **拍照/看摄像头**：说“拍一张 / 拍个照 / 看看家里 / 摄像头看一下”→ `photo.sh`（默认 1920x1080，自动发到来源会话）。要特定分辨率/连拍加 `--size`、`--burst`。
# @order 10
# 用法:
#   photo.sh                         # 1920x1080 拍一张发文件传输助手
#   photo.sh --to 小王                # 发给指定会话
#   photo.sh --size 2560x1440        # 指定分辨率（不支持则自动降级 1280x720/640x480）
#   photo.sh --device /dev/video0    # 指定摄像头
#   photo.sh --burst 3               # 连拍 3 张（间隔 1s）全发
#   photo.sh --save /tmp/a.jpg       # 指定保存路径
#   photo.sh --no-send               # 只拍不发，返回路径
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${DISPLAY:-:0}"
exec luajit "$DIR/photo.lua" "$@"
