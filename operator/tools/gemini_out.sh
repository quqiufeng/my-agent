#!/usr/bin/env bash
# operator/tools/gemini_out.sh — 把（Gemini 等）获取到的结果按目标转发
#
# 用法:
#   gemini_out.sh <wechat|opencode> "文本"
#   echo "多行文本" | gemini_out.sh <wechat|opencode>
#
#   wechat   → 发到微信（默认文件传输助手）
#   opencode → curl 回 opencode 的 tmux(/tui)，并加 [Gemini] 前缀，供大脑继续处理
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_URL="${AGENT_URL:-http://localhost:4097}"

TARGET="${1:-}"
[ $# -gt 0 ] && shift || true
TEXT="${*:-}"

# 没给文本参数则从 stdin 读
if [ -z "$TEXT" ] && [ ! -t 0 ]; then
    TEXT="$(cat)"
fi

if [ -z "$TARGET" ] || [ -z "$TEXT" ]; then
    echo "用法: $0 <wechat|opencode> \"文本\"   （文本也可从 stdin 读）" >&2
    exit 2
fi

case "$(echo "$TARGET" | tr 'A-Z' 'a-z')" in
    wechat|wx|weixin)
        exec "$DIR/wechat_send.sh" "$TEXT"
        ;;
    opencode|oc|tui)
        # 用 jq 生成合法 JSON（含 [Gemini] 前缀），避免转义问题
        TMP="$(mktemp)"
        jq -Rs '{text: ("[Gemini] " + .)}' <<<"$TEXT" > "$TMP" || { echo "jq 生成 JSON 失败" >&2; rm -f "$TMP"; exit 1; }
        curl -sf -X POST -H 'Content-Type: application/json' --data-binary @"$TMP" \
            "$AGENT_URL/tui/append-prompt" >/dev/null || { echo "转发 opencode 失败（TUI 未运行？）" >&2; rm -f "$TMP"; exit 1; }
        curl -sf -X POST -H 'Content-Type: application/json' -d '{}' \
            "$AGENT_URL/tui/submit-prompt" >/dev/null || { echo "submit 失败" >&2; rm -f "$TMP"; exit 1; }
        rm -f "$TMP"
        echo "已发送到 opencode(/tui)"
        ;;
    *)
        echo "未知目标: $TARGET（可用 wechat | opencode）" >&2
        exit 2
        ;;
esac
