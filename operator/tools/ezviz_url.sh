#!/usr/bin/env bash
# tools/ezviz_url.sh — 刷新萤石摄像头直播地址（纯 API，LuaJIT 实现）
# @desc 刷新萤石摄像头直播地址（纯 API）：用 ~/.env 的 appKey/appSecret 换 token → 取 HLS 播放地址（protocol=2）→ 写入指定文件；若设备加密已开启，自动用验证码关闭后重试
# @usage tools/ezviz_url.sh [序列号] [输出文件]   # 默认 802657358 → /tmp/myagent_ezviz.url；门口 815311181 → /tmp/myagent_door.url
# @rule 萤石某路黑屏/过期时 → 重新跑本工具生成该路地址；app 重连即自动跟随（app 各路读各自文件：客厅 /tmp/myagent_ezviz.url、门口 /tmp/myagent_door.url）
# @order 42
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/ezviz_url.lua" "$@"
