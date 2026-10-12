#!/usr/bin/env bash
# tools/chrome_debug.sh — 启动「固定调试端口」的 Chrome（供 MCP 免授权连接）
# @desc 用固定调试端口启动专用 profile 的 Chrome，供 chrome-devtools MCP(--browser-url) 连接（免反复授权）
# @usage tools/chrome_debug.sh [端口]        # 默认 9222
# @rule 需要 Chrome 供 MCP 使用时 → 先 `tools/chrome_debug.sh`（固定端口实例，免弹授权）；不要用系统默认 Chrome 直连。
# @order 16
set -uo pipefail
PORT="${1:-9222}"
DEB="$HOME/.chrome-debug-profile"

# 已在跑则直接返回
if ss -ltn 2>/dev/null | grep -q ":${PORT} "; then
    echo "Chrome 已在端口 ${PORT} 运行"; exit 0
fi

# 首次：用当前默认 profile 生成专用目录（保留登录态；排除大缓存/端上模型）
if [ ! -d "$DEB/Default" ]; then
    echo "创建专用 profile（拷贝登录数据）..."
    mkdir -p "$DEB/Default"
    rsync -a "$HOME/.config/google-chrome/Local State" "$DEB/" 2>/dev/null || true
    rsync -a --exclude 'Cache/' --exclude 'Code Cache/' --exclude 'GPUCache/' \
        --exclude 'ShaderCache/' --exclude 'GrShaderCache/' --exclude 'Service Worker/' \
        --exclude 'Crash Reports/' "$HOME/.config/google-chrome/Default/" "$DEB/Default/" 2>/dev/null || true
fi

# 关闭其它 Chrome（同一端口不能被两个实例占用；且默认 profile 实例会抢端口）
for pid in $(ps -eo pid,comm | awk '$2=="chrome"{print $1}'); do kill -9 "$pid" 2>/dev/null; done
sleep 2

# 会话内启动
P=$(pgrep -x pcmanfm-qt | head -1)
XA=$(tr '\0' '\n' < "/proc/$P/environ" 2>/dev/null | sed -n 's/^XAUTHORITY=//p')
setsid env DISPLAY=:0 XAUTHORITY="$XA" google-chrome \
    --remote-debugging-port="$PORT" --user-data-dir="$DEB" \
    --no-first-run --no-default-browser-check \
    >/tmp/opencode/chrome_debug.log 2>&1 </dev/null &
sleep 5
if ss -ltn 2>/dev/null | grep -q ":${PORT} "; then
    echo "Chrome 已启动（端口 ${PORT}），可直接用 MCP"
else
    echo "启动失败，见 /tmp/opencode/chrome_debug.log" >&2; exit 1
fi
