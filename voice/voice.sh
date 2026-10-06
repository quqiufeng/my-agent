#!/usr/bin/env bash
# voice/voice.sh — 语音模块统一入口
# 用法:
#   voice.sh say   "文本"      # 文本转语音 → USB 音响
#   voice.sh listen [--once]   # 麦克风常驻监听 → 识别 → 转发 Master
#   voice.sh tutor             # 英语口语陪练（[英语口语] 前缀 + 英文音色）
#   voice.sh once              # 识别一句即退出（验证用）
#   voice.sh test              # 自检：合成并播放一句
#   voice.sh camera [参数]     # 摄像头窗口（USB + RTSP 分屏）
#   voice.sh app    [参数]     # 统一界面（画面+人脸门控+语音监听+状态栏）
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cmd="${1:-}"; shift || true

case "$cmd" in
    say)    exec "$DIR/say.sh" "$@" ;;
    listen) exec "$DIR/listen.sh" "$@" ;;
    tutor|english) exec "$DIR/tutor.sh" "$@" ;;
    once)   exec "$DIR/listen.sh" --once --no-forward "$@" ;;
    test)   exec "$DIR/say.sh" "${*:-你好，我是星期五，语音模块自检正常。}" ;;
    camera) exec "$DIR/camera.sh" "$@" ;;
    app|ui) exec "$DIR/app.sh" "$@" ;;
    orb|ball) exec "$DIR/orb.sh" "$@" ;;
    *)
        echo "用法: $0 {say <文本>|listen|once|test|camera|app|orb}" >&2
        exit 2
        ;;
esac
