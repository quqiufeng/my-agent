#!/usr/bin/env bash
# tools/wechat_shot.sh — 截屏发微信：微信 Alt+A 截当前前台画面(全屏) → 剪贴板 → 粘贴到会话 → 回车发送
# Alt+A 是微信全局快捷键，无需先激活微信；截到的是「按下时前台显示的内容」（浏览器/地图/桌面等）。
# 依赖微信客户端运行且已绑定全局快捷键 Alt+A（双击=取全屏）。
# @desc 截屏发微信（微信 Alt+A 截当前屏幕 → 剪贴板 → 粘贴发送到指定会话/文件传输助手）
# @usage tools/wechat_shot.sh            # 截图发到文件传输助手
#        tools/wechat_shot.sh --to 小王   # 截图发到「小王」
# @rule **截屏发我 / 截图发我 / 屏幕发我** → `tools/wechat_shot.sh`（可选 `--to <会话名>`）。截取当前屏幕并用微信发送。若用户想截的是某个网页/地图，先用浏览器打开并置于前台再调用。
# @order 22
set -uo pipefail
export DISPLAY="${DISPLAY:-:0}"
DIR="$(cd "$(dirname "$0")" && pwd)"

TO="文件传输助手"; APP=""
while [ $# -gt 0 ]; do
    case "$1" in
        --to) TO="${2:-文件传输助手}"; shift 2 ;;
        --app) APP="${2:-}"; shift 2 ;;
        *) shift ;;
    esac
done

SHOT="/tmp/myagent_shot_$$.png"
trap 'rm -f "$SHOT"' EXIT

# 抓图：默认「显示桌面」——最小化所有可见窗口抓全屏再恢复；--app <名> 则先调出该应用
if [ -n "$APP" ]; then
    wmctrl -a "$APP" 2>/dev/null || xdotool search --name "$APP" windowactivate 2>/dev/null
    sleep 1.0
    import -window root "$SHOT"
else
    VIS="$(mktemp)"
    wmctrl -l | awk '$4!~/pcmanfm-desktop|LXQt/{print $1}' > "$VIS"
    while read -r w; do xdotool windowminimize "$w" 2>/dev/null; done < "$VIS"
    sleep 1.0
    import -window root "$SHOT"
    while read -r w; do xdotool windowmap "$w" 2>/dev/null; wmctrl -i -r "$w" -b remove,hidden 2>/dev/null; done < "$VIS"
    rm -f "$VIS"
fi

# 2) 已把图片转存到文件（后面搜索会话要用剪贴板输入中文，会覆盖它）
if [ ! -s "$SHOT" ]; then
    echo "截图失败：剪贴板里没有图片" >&2
    exit 1
fi

# 3) 发送图片：走可靠的 wechat_send_file 通道（已验证能到）
"$DIR/wechat_send_file.sh" "$SHOT" --to "$TO"
