#!/usr/bin/env bash
# tools/living_chrome.sh — 在客厅小机箱的 Chrome 打开指定网页（HDMI → Sony 电视）
# @desc 远程控制客厅小机箱 Chrome 打开网页（小机箱 HDMI 输出到 Sony 电视）
# @usage tools/living_chrome.sh open <http/https URL>
# @rule 说“客厅电视/小机箱打开网页/放某个网页” → tools/living_chrome.sh open <URL>；只允许 http/https。
# @order 48
set -uo pipefail

HOST="${SMALLPC_HOST:-quqiufeng@192.168.1.105}"
PORT="${SMALLPC_CDP_PORT:-9222}"

usage() {
    echo "用法: tools/living_chrome.sh open <http/https URL>" >&2
    exit 2
}

[ "${1:-}" = "open" ] || usage
URL="${2:-}"
[ -n "$URL" ] || usage
case "$URL" in
    http://*|https://*) ;;
    *) echo "只允许 http/https URL" >&2; exit 2 ;;
esac

# URL encode for Chrome DevTools /json/new
ENC="$(python3 - "$URL" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
)"

remote() {
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" "$@"
}

# 确保小机箱上的调试 Chrome 在跑
if ! remote "curl -fsS --max-time 2 http://127.0.0.1:${PORT}/json/version >/dev/null 2>&1"; then
    remote "bash -s" <<REMOTE
set -e
PORT="$PORT"
AUTH="\$(ps -eo args | grep '[X]org' | sed -n 's/.*-auth \\([^ ]*\\).*/\\1/p' | head -1)"
[ -n "\$AUTH" ] || { echo '找不到 Xorg XAUTHORITY' >&2; exit 1; }
sudo -n env DISPLAY=:0 XAUTHORITY="\$AUTH" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/\$(id -u)/bus" \
  runuser -u "\$(id -un)" -- nohup google-chrome \
  --remote-debugging-port="\$PORT" --remote-allow-origins='*' \
  --user-data-dir="\$HOME/.chrome-debug" \
  --no-first-run --no-default-browser-check about:blank \
  >/tmp/living-chrome.log 2>&1 </dev/null &
REMOTE
    for _ in $(seq 1 20); do
        remote "curl -fsS --max-time 1 http://127.0.0.1:${PORT}/json/version >/dev/null 2>&1" && break
        sleep 0.5
    done
    remote "curl -fsS --max-time 2 http://127.0.0.1:${PORT}/json/version >/dev/null 2>&1" || {
        echo "小机箱 Chrome 调试端口未启动，见 /tmp/living-chrome.log" >&2
        exit 1
    }
fi

RESP="$(remote "curl -fsS -X PUT 'http://127.0.0.1:${PORT}/json/new?${ENC}'")" || {
    echo "打开页面失败" >&2; exit 1
}
ID="$(printf '%s' "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)"
if [ -n "$ID" ]; then
    remote "curl -fsS 'http://127.0.0.1:${PORT}/json/activate/${ID}' >/dev/null 2>&1" || true
fi
echo "已打开: $URL"
