#!/usr/bin/env bash
# voice/tutor.sh — 英语口语陪练入口
# 说英文 → 识别 → 以 [英语口语] 前缀转发大脑；大脑用英文回应并纠错，
# 回复经 say.sh 用英文音色朗读（陪练模式 say.sh 自动切英文 voice）。
# 用法: tutor.sh [--once] [--no-forward]
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=config.sh
. "$DIR/config.sh"

export VOICE_PREFIX="[英语口语]"
export VOICE_ALWAYS=1
export SENSEVOICE_LANG="${SENSEVOICE_LANG_EN:-auto}"
export KOKORO_SID="${KOKORO_SID_EN:-3}"
export VOICE_WAKE=""          # 陪练不需要唤醒词（配合 VOICE_ALWAYS=1）

FLAG="/tmp/myagent_english_mode"
touch "$FLAG" 2>/dev/null
trap 'rm -f "$FLAG"' EXIT INT TERM

echo "[tutor] 英语口语陪练已开启：直接说英文即可，回复会用英文音色朗读；Ctrl+C 退出。"
exec "$DIR/listen.sh" "$@"
