#!/usr/bin/env bash
# tools/say.sh — USB 音响播放语音（文本转语音）
# @desc USB 音响发声（TTS）；可用 --voice 指定克隆音色
# @usage tools/say.sh [--voice <音色名>] "文本"
# @rule **出声/朗读/语音回**：用 `tools/say.sh "文本"`；想用**克隆音色**发声则 `tools/say.sh --voice <音色名> "文本"`（音色用 `tools/voices.sh` 管理：list/add）。
# @order 5
exec /opt/my-agent/voice/say.sh "$@"
