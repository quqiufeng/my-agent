#!/usr/bin/env bash
# run.sh — 启动 my-agent 桌面界面（未构建会先构建）
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUNDLE="$HERE/build/linux/x64/release/bundle"; BIN="$BUNDLE/myagent_ui"
# 运行期库：语音/OCR/C 依赖（后续 FFI 用）
export LD_LIBRARY_PATH="$ROOT/voice/libs:$ROOT/libs:$ROOT/agentkit/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:${LD_LIBRARY_PATH:-}"
[ -x "$BIN" ] || { echo "尚未构建，编译中 ..."; "$HERE/build.sh" || { echo "构建失败" >&2; exit 1; }; }
# 第二路（手机后摄）默认启用；可用环境变量覆盖
export CAM2_URL="${CAM2_URL:-http://192.168.1.99:8080/video}"
# 手机当麦克风：touch /tmp/myagent_phone_mic 启用（否则用本机声卡）
[ -f /tmp/myagent_phone_mic ] && export VOICE_MIC_URL="${VOICE_MIC_URL:-http://192.168.1.99:8080/audio}"
# 手机画面默认旋转 90°（竖放），/tmp 每次重启清空时补上；运行中改此文件后需重连生效
[ -f /tmp/myagent_ezviz.rot ] || echo 90 > /tmp/myagent_ezviz.rot
exec "$BIN" "$@"
