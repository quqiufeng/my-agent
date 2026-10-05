#!/usr/bin/env bash
# voice/config.sh — 语音模块公共配置（被其他脚本 source）
# 所有项均可用同名环境变量覆盖。

# ── 语音识别（SenseVoice.cpp，纯 C++） ─────────────────────────
export SENSEVOICE_BIN="${SENSEVOICE_BIN:-/opt/SenseVoice.cpp/bin/sense-voice-main}"
export SENSEVOICE_MODEL="${SENSEVOICE_MODEL:-/data/models/sense-voice-small-q4_k.gguf}"
export SENSEVOICE_LANG="${SENSEVOICE_LANG:-zh}"
export SENSEVOICE_THREADS="${SENSEVOICE_THREADS:-4}"
export VOICE_MIC_DEV="${VOICE_MIC_DEV:-plughw:2,0}"   # ALSA 采集设备
export VOICE_MIC_CARD="${VOICE_MIC_CARD:-2}"          # 用于 amixer 增益
export VOICE_MIC_GAIN="${VOICE_MIC_GAIN:-7810}"       # 麦克风采集音量（max=7810）

# ── 语音合成（sherpa-onnx + Kokoro，纯 C++） ──────────────────
export SHERPA_BIN="${SHERPA_BIN:-/opt/sherpa-onnx/bin/sherpa-onnx-offline-tts}"
export SHERPA_LIB="${SHERPA_LIB:-/opt/sherpa-onnx/lib}"
export KOKORO_DIR="${KOKORO_DIR:-/data/models/kokoro-multi-lang-v1_0}"
export KOKORO_SID="${KOKORO_SID:-47}"                 # 47=zf_xiaoxiao 中文女声
export TTS_THREADS="${TTS_THREADS:-4}"
export VOICE_SPEAKER="${VOICE_SPEAKER:-plughw:3,0}"   # ALSA 兜底设备（USB 音响）
export VOICE_SINK="${VOICE_SINK:-}"                   # PipeWire sink（留空=默认，本机默认即 DTC 480）
export TTS_OUT="${TTS_OUT:-/tmp/voice_tts.wav}"

# ── 唤醒词（语音交互模式） ────────────────────────────────────
# 只有听到唤醒词才响应，否则静默；命中唤醒词后 VOICE_ACTIVE_MS 内持续响应后续指令。
# 若此时正在放歌（存在 /tmp/myagent_music.pid 且进程存活），唤醒即暂停音乐，窗口结束自动恢复。
export VOICE_WAKE="${VOICE_WAKE:-你好星期五,星期五}"   # 逗号分隔多个唤醒词
export VOICE_ACTIVE_MS="${VOICE_ACTIVE_MS:-10000}"     # 唤醒后持续响应窗口（毫秒）

# ── 处理中心（opencode Master） ───────────────────────────────
export AGENT_URL="${AGENT_URL:-http://localhost:4097}"
