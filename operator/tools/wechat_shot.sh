#!/usr/bin/env bash
# tools/wechat_shot.sh — 截屏发微信
# @desc 截屏发微信：说「截图/截屏 <应用名>」则截该应用；不给应用则截桌面。发送到指定会话/文件传输助手
# @usage tools/wechat_shot.sh [--to 会话] [--app 应用名]
# @rule **截屏发我 / 截图发我** → `tools/wechat_shot.sh`（不加 --app 截的是桌面）。**要截某个应用**（如“截图 agent / 助手 / 微信 / 浏览器”）→ **必须** `tools/wechat_shot.sh --app <应用名>`。
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

# 抓图：--app <名> 先按标题/类名模糊匹配调出该应用；否则「显示桌面」截全屏
capture_desktop() {
    local VIS; VIS="$(mktemp)"
    wmctrl -l | awk '$4!~/pcmanfm-desktop|LXQt/{print $1}' > "$VIS"
    while read -r w; do xdotool windowminimize "$w" 2>/dev/null; done < "$VIS"
    sleep 1.0
    import -window root "$SHOT"
    while read -r w; do xdotool windowmap "$w" 2>/dev/null; wmctrl -i -r "$w" -b remove,hidden 2>/dev/null; done < "$VIS"
    rm -f "$VIS"
}

if [ -n "$APP" ]; then
    case "$APP" in
        助手|ai助手|AI助手|myagent|my-agent|my_agent|我的助手|语音助手|星期五|agent应用|agent) APP=agent ;;
        浏览器|谷歌浏览器|chrome浏览器|网页|chrome) APP=chrome ;;
        终端|命令行|terminal) APP=qterminal ;;
        文件管理器|文件夹|文件) APP=pcmanfm ;;
    esac
    q=$(printf '%s' "$APP" | tr 'A-Z' 'a-z')
    TARGET=""
    for w in $(wmctrl -l | awk '{print $1}'); do
        t=$(xdotool getwindowname "$w" 2>/dev/null | tr 'A-Z' 'a-z')
        c=$(xprop -id "$w" WM_CLASS 2>/dev/null | tr 'A-Z' 'a-z')
        case "$t$c" in *"$q"*) TARGET="$w"; break ;; esac
    done
    if [ -n "$TARGET" ]; then
        wmctrl -i -a "$TARGET" 2>/dev/null; sleep 1.0
        import -window root "$SHOT"
    else
        echo "[wechat_shot] 未找到应用 '$APP'，改截桌面" >&2
        capture_desktop
    fi
else
    capture_desktop
fi

# 2) 已把图片转存到文件（后面搜索会话要用剪贴板输入中文，会覆盖它）
if [ ! -s "$SHOT" ]; then
    echo "截图失败：剪贴板里没有图片" >&2
    exit 1
fi

# 3) 发送图片：走可靠的 wechat_send_file 通道（已验证能到）
"$DIR/wechat_send_file.sh" "$SHOT" --to "$TO"
