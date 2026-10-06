#!/usr/bin/env bash
# tools/phone.sh — 通过 USB/ADB 控制已连接的安卓手机（截屏/点击/滑动/按键/输入/应用/装包）
# 前提：手机已开「USB 调试」并在弹窗中点过「允许」；用 `tools/phone.sh status` 可查。
# @desc 控制连接的安卓手机：截屏、点击、滑动、按键、输入(含中文)、打开应用、列出/安装应用
# @usage tools/phone.sh status                        # 查看是否已连接
#        tools/phone.sh screen [输出.png]             # 手机截屏→存文件→输出路径（再用 wechat_send_file.sh 发回）
#        tools/phone.sh tap X Y                       # 按坐标点击（先用 screen 看图定坐标，手机约 1080x2400）
#        tools/phone.sh swipe X1 Y1 X2 Y2 [毫秒]      # 滑动
#        tools/phone.sh text "ASCII 文本"             # 输入文本（仅英文/数字/符号）
#        tools/phone.sh type "任意文本（含中文）"      # 输入文本（自动切 ADBKeyboard，支持中文，用完复原输入法）
#        tools/phone.sh key HOME|BACK|ENTER|POWER|WAKEUP|...  # 按系统键
#        tools/phone.sh home | back | wake            # 常用键快捷方式
#        tools/phone.sh open <包名>                   # 启动应用（包名，如 com.tencent.mm）
#        tools/phone.sh find <关键字>                 # 搜索已安装应用包名
#        tools/phone.sh apps                          # 列出第三方应用包名
#        tools/phone.sh install <apk路径>             # 安装 APK
# @rule **手机操作**：用户说“看下手机/手机截个屏/操作手机”→ 用 `tools/phone.sh screen` 得路径，再 `tools/wechat_send_file.sh <路径>` 发回；要点击/滑动/输入/打开应用就用对应子命令（中文输入用 `phone.sh type`）。**只用白名单子命令**，不要拼 `adb` 原始命令。
# @order 23
set -uo pipefail

ADB="${ADB:-adb}"

require_device() {
    local state
    state="$("$ADB" get-state 2>/dev/null)"
    if [ "$state" != "device" ]; then
        local line
        line="$("$ADB" devices 2>/dev/null | sed -n '2p')"
        if printf '%s' "$line" | grep -q unauthorized; then
            echo "手机未授权：请在手机屏幕上点「允许 USB 调试」" >&2
        else
            echo "未检测到手机：请用数据线连接并开启 USB 调试" >&2
        fi
        exit 1
    fi
}

cmd="${1:-status}"; shift || true

case "$cmd" in
    status)
        "$ADB" start-server >/dev/null 2>&1
        out="$("$ADB" devices -l 2>/dev/null | sed -n '2p')"
        if [ -z "$out" ]; then echo "未连接手机"; exit 1; fi
        echo "$out"
        if "$ADB" get-state 2>/dev/null | grep -q '^device$'; then
            echo "型号: $("$ADB" shell getprop ro.product.model 2>/dev/null)"
            echo "安卓: $("$ADB" shell getprop ro.build.version.release 2>/dev/null)"
            echo "分辨率: $("$ADB" shell wm size 2>/dev/null | sed 's/Physical size: //')"
        fi
        ;;
    screen)
        require_device
        out="${1:-/tmp/phone_$(date +%Y%m%d_%H%M%S).png}"
        "$ADB" exec-out screencap -p > "$out" 2>/dev/null || { echo "截屏失败" >&2; exit 1; }
        [ -s "$out" ] || { echo "截屏失败（空文件）" >&2; exit 1; }
        echo "$out"
        ;;
    tap)
        require_device
        [ $# -ge 2 ] || { echo "用法: phone.sh tap X Y" >&2; exit 2; }
        "$ADB" shell input tap "$1" "$2"
        ;;
    swipe)
        require_device
        [ $# -ge 4 ] || { echo "用法: phone.sh swipe X1 Y1 X2 Y2 [毫秒]" >&2; exit 2; }
        "$ADB" shell input swipe "$1" "$2" "$3" "$4" "${5:-300}"
        ;;
    text)
        require_device
        [ $# -ge 1 ] || { echo "用法: phone.sh text \"文本\"" >&2; exit 2; }
        "$ADB" shell input text "$1"
        ;;
    type)
        require_device
        [ $# -ge 1 ] || { echo "用法: phone.sh type \"文本\"" >&2; exit 2; }
        # 中文靠 ADBKeyboard 广播注入；用完恢复原输入法
        prev="$("$ADB" shell settings get secure default_input_method 2>/dev/null | tr -d '\r')"
        "$ADB" shell ime enable com.android.adbkeyboard/.AdbIME >/dev/null 2>&1
        "$ADB" shell ime set com.android.adbkeyboard/.AdbIME >/dev/null 2>&1
        sleep 1
        b64="$(printf '%s' "$1" | base64 -w0)"
        "$ADB" shell am broadcast -a ADB_INPUT_B64 --es msg "$b64" >/dev/null 2>&1
        sleep 0.6
        if [ -n "$prev" ] && [ "$prev" != "com.android.adbkeyboard/.AdbIME" ]; then
            "$ADB" shell ime set "$prev" >/dev/null 2>&1
        fi
        ;;
    key)
        require_device
        [ $# -ge 1 ] || { echo "用法: phone.sh key KEYCODE" >&2; exit 2; }
        "$ADB" shell input keyevent "$1"
        ;;
    home) require_device; "$ADB" shell input keyevent KEYCODE_HOME ;;
    back) require_device; "$ADB" shell input keyevent KEYCODE_BACK ;;
    wake) require_device; "$ADB" shell input keyevent KEYCODE_WAKEUP ;;
    open)
        require_device
        [ $# -ge 1 ] || { echo "用法: phone.sh open <包名>" >&2; exit 2; }
        "$ADB" shell monkey -p "$1" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 \
            || { echo "启动失败：$1（用 find 确认包名）" >&2; exit 1; }
        echo "已启动 $1"
        ;;
    find)
        require_device
        [ $# -ge 1 ] || { echo "用法: phone.sh find <关键字>" >&2; exit 2; }
        "$ADB" shell pm list packages 2>/dev/null | sed 's/^package://' | grep -i -- "$1" || echo "无匹配"
        ;;
    apps)
        require_device
        "$ADB" shell pm list packages -3 2>/dev/null | sed 's/^package://'
        ;;
    install)
        require_device
        [ $# -ge 1 ] || { echo "用法: phone.sh install <apk路径>" >&2; exit 2; }
        "$ADB" install -r "$1"
        ;;
    *)
        echo "未知子命令: $cmd（status/screen/tap/swipe/text/type/key/home/back/wake/open/find/apps/install）" >&2
        exit 2
        ;;
esac
