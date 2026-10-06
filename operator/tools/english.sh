#!/usr/bin/env bash
# tools/english.sh — 英语口语陪练：开/关麦克风陪练（后台跑 voice/voice.sh tutor）
# @desc 英语口语陪练（麦克风识别英文，回复用英文音色朗读）
# @usage tools/english.sh start|stop|status
# @rule **英语口语陪练**：收到 `[英语口语] ...` 时，你是英语口语陪练——用**英文**简短回应（1-3 句）、温和指出更自然的说法，并反问一句让对话继续；回复一律 `tools/say.sh "英文"` 读出（陪练模式会自动用英文音色）。用户说中文或要翻译时，再中英对照。
# @order 14
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
VOICE="${VOICE_DIR:-/opt/my-agent/voice}"
FLAG=/tmp/myagent_english_mode
SESS="${ENGLISH_TMUX:-english}"

case "${1:-status}" in
    start)
        if tmux has-session -t "$SESS" 2>/dev/null; then echo "陪练已在运行"; exit 0; fi
        pgrep -f "voice.sh tutor" >/dev/null 2>&1 && { echo "陪练已在运行"; exit 0; }
        tmux new-session -d -s "$SESS" "cd '$VOICE' && DISPLAY=:0 ./voice.sh tutor 2>&1 | tee /tmp/english.log"
        sleep 2
        echo "已开启英语陪练（直接说英文即可，回复会朗读）；tmux attach -t $SESS 可看实时识别"
        ;;
    stop)
        tmux kill-session -t "$SESS" 2>/dev/null
        pkill -f "voice.sh tutor" 2>/dev/null
        rm -f "$FLAG"
        echo "已关闭英语陪练"
        ;;
    status)
        if tmux has-session -t "$SESS" 2>/dev/null || pgrep -f "voice.sh tutor" >/dev/null 2>&1; then
            echo "陪练：运行中"
        else
            echo "陪练：未运行"
        fi
        ;;
    *)
        echo "用法: english.sh start|stop|status" >&2; exit 2
        ;;
esac
