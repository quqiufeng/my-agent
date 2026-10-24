#!/usr/bin/env bash
# tools/phone.sh — 通过 USB/ADB 控制已连接的安卓手机（LuaJIT 实现）
# 前提：手机已开「USB 调试」并在弹窗中点过「允许」；用 `tools/phone.sh status` 可查。
# @desc 控制连接的安卓手机：截屏、点击、滑动、按键、输入(含中文)、打开应用、列出/安装应用
# @usage tools/phone.sh status                        # 查看是否已连接
#        tools/phone.sh screen [输出.png]             # 手机截屏→存文件→输出路径（再用 wechat_send_file.sh 发回）
#        tools/phone.sh tap X Y                       # 按坐标点击（先用 screen 看图定坐标，手机约 1080x2400）
#        tools/phone.sh swipe X1 Y1 X2 Y2 [毫秒]      # 滑动
#        tools/phone.sh text "ASCII 文本"             # 输入文本（仅英文/数字/符号）
#        tools/phone.sh type "任意文本（含中文）"     # 输入文本（自动切 ADBKeyboard，支持中文，用完复原输入法）
#        tools/phone.sh key HOME|BACK|ENTER|POWER|WAKEUP|...  # 按系统键
#        tools/phone.sh home | back | wake            # 常用键快捷方式
#        tools/phone.sh open <包名>                   # 启动应用（包名，如 com.tencent.mm）
#        tools/phone.sh find <关键字>                 # 搜索已安装应用包名
#        tools/phone.sh apps                          # 列出第三方应用包名
#        tools/phone.sh install <apk路径>             # 安装 APK
# @rule **手机操作**：用户说“看下手机/手机截个屏/操作手机”→ 用 `tools/phone.sh screen` 得路径，再 `tools/wechat_send_file.sh <路径>` 发回；要点击/滑动/输入/打开应用就用对应子命令（中文输入用 `phone.sh type`）。**只用白名单子命令**，不要拼 `adb` 原始命令。
# @order 23
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/phone.lua" "$@"
