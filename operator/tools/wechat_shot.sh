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

TO="文件传输助手"
if [ "${1:-}" = "--to" ]; then TO="${2:-文件传输助手}"; fi

SHOT="/tmp/myagent_shot_$$.png"
trap 'rm -f "$SHOT"' EXIT
read -r SW SH < <(xdotool getdisplaygeometry)

# 1) 微信全局快捷键 Alt+A 截当前前台画面(全屏) → 进剪贴板
#    非微信前台：双击即可取全屏（快）。
#    微信在前台：双击会只截到空图，须改用「拖拽框选整屏 + 双击」。
grab() {
    xdotool key --clearmodifiers alt+a
    sleep 1.0
    xdotool mousemove "$((SW / 2))" "$((SH / 2))"; sleep 0.3
    xdotool click --repeat 2 --delay 130 1
    sleep 1.3
    xclip -selection clipboard -t image/png -o > "$SHOT" 2>/dev/null
}
grab
# 图过小（微信在前台时常见，约 90B 空图）→ 拖拽框选整屏重试
if [ ! -s "$SHOT" ] || [ "$(stat -c%s "$SHOT" 2>/dev/null || echo 0)" -lt 2000 ]; then
    xdotool key --clearmodifiers alt+a
    sleep 1.0
    xdotool mousemove 0 0; sleep 0.2
    xdotool mousedown 1; sleep 0.2
    xdotool mousemove "$((SW - 1))" "$((SH - 1))"; sleep 0.3
    xdotool mouseup 1; sleep 0.3
    xdotool mousemove "$((SW / 2))" "$((SH / 2))"; sleep 0.2
    xdotool click --repeat 2 --delay 130 1
    sleep 1.3
    xclip -selection clipboard -t image/png -o > "$SHOT" 2>/dev/null
fi

# 2) 已把图片转存到文件（后面搜索会话要用剪贴板输入中文，会覆盖它）
if [ ! -s "$SHOT" ]; then
    echo "截图失败：剪贴板里没有图片" >&2
    exit 1
fi

# 3) 打开目标会话并聚焦输入框
export LD_LIBRARY_PATH="/opt/my-agent/wechat-ocr/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:${LD_LIBRARY_PATH:-}"
export LUA_PATH="/opt/my-agent/wechat-ocr/?.lua;/opt/my-agent/wechat-ocr/lua/?.lua;/opt/my-agent/wechat-ocr/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;"
export WECHAT_TO="$TO"
luajit "$DIR/wechat_shot.lua" >/dev/null || { echo "进入会话失败：$TO" >&2; exit 1; }

# 4) 把图片放回剪贴板 → 粘贴到输入框 → 等暂存完成 → 回车发送
#    （xclip 需常驻持有选区；Ctrl+V 后要等图片上传/暂存完成，否则回车发不出去）
nohup setsid xclip -selection clipboard -t image/png -i "$SHOT" </dev/null >/dev/null 2>&1 &
sleep 1.0
xdotool key --clearmodifiers ctrl+v
sleep 4.0
# 确保焦点在微信输入框（robot 搜索后偶发焦点漂移），再回车；连按两次兜底
eval "$(xdotool getactivewindow getwindowgeometry --shell 2>/dev/null)"
if [ -n "${WIDTH:-}" ]; then
    xdotool mousemove "$((X + WIDTH * 47 / 100))" "$((Y + HEIGHT * 874 / 100))" click 1 2>/dev/null
    sleep 0.5
fi
xdotool key --clearmodifiers Return
sleep 1.2
xdotool key --clearmodifiers Return
sleep 0.8

echo "已截屏并发送 -> $TO"
