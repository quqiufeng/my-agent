#!/usr/bin/env bash
# tools/netmap.sh — 扫描局域网、识别设备、更新拓扑与音视频源（LuaJIT 实现）
# @desc 扫描局域网并识别设备：读取 ARP/主机名/端口/摄像头信息，生成 devices.json、NETWORK.md 和 devices.env；供其他工具动态读取 IP 与音视频源
# @usage tools/netmap.sh scan | show | sources
# @rule 说“扫描设备/看网络拓扑/更新设备 IP/刷新摄像头地址”→ `tools/netmap.sh scan`；只看当前结果用 `show`/`sources`。
# @order 3
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/netmap.lua" "$@"
