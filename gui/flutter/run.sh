#!/usr/bin/env bash
# run.sh — 启动 my-agent 桌面界面（未构建会先构建）
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUNDLE="$HERE/build/linux/x64/release/bundle"; BIN="$BUNDLE/myagent_ui"
# 运行期库：语音/OCR/C 依赖（后续 FFI 用）
export LD_LIBRARY_PATH="$ROOT/voice/libs:$ROOT/libs:$ROOT/agentkit/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:${LD_LIBRARY_PATH:-}"
[ -x "$BIN" ] || { echo "尚未构建，编译中 ..."; "$HERE/build.sh" || { echo "构建失败" >&2; exit 1; }; }
# 第二路（可选）：手机 / 萤石 / camhost 的 MJPEG 都行，需要时自己 export
# export CAM2_URL=http://192.168.1.68:8080/video
# 网络麦克风：/tmp/myagent_net_mic 里写 URL 即启用（客厅 Ejoy / 手机 /audio 都行）
if [ -f /tmp/myagent_net_mic ]; then
    export VOICE_MIC_URL="${VOICE_MIC_URL:-$(head -n1 /tmp/myagent_net_mic)}"
fi
# 本机声卡 + 网络麦混音：touch /tmp/myagent_voice_mix 启用
[ -f /tmp/myagent_voice_mix ] && export VOICE_MIC_MIX="${VOICE_MIC_MIX:-1}"
# 手机画面默认旋转 90°（竖放），/tmp 每次重启清空时补上；运行中改此文件后需重连生效
[ -f /tmp/myagent_ezviz.rot ] || echo 90 > /tmp/myagent_ezviz.rot
exec "$BIN" "$@"
