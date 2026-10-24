#!/usr/bin/env bash
# run.sh — 启动 my-agent 桌面界面（未构建会先构建）
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUNDLE="$HERE/build/linux/x64/release/bundle"; BIN="$BUNDLE/myagent_ui"
# 运行期库：语音/OCR/C 依赖（后续 FFI 用）
export LD_LIBRARY_PATH="$ROOT/voice/libs:$ROOT/libs:$ROOT/agentkit/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:${LD_LIBRARY_PATH:-}"
# 设备注册表：netmap.sh 生成的四路标签/地址（不含密码）
if [ -f "$ROOT/operator/devices.env" ]; then
    set -a
    . "$ROOT/operator/devices.env"
    set +a
fi
[ -x "$BIN" ] || { echo "尚未构建，编译中 ..."; "$HERE/build.sh" || { echo "构建失败" >&2; exit 1; }; }
# 首页默认四路：USB + EZVIZ 客厅 + EZVIZ 门口 + TP-Link
# 地址来源：/tmp/myagent_ezviz.url、/tmp/myagent_door.url、~/.env 的 TPLINK_RTSP
# 需要换源时可用 CAM2_URL / CAM3_URL / CAM4_URL 覆盖。
# 网络麦克风：/tmp/myagent_net_mic 里写 URL 即启用（客厅 Ejoy / 手机 /audio 都行）
if [ -f /tmp/myagent_net_mic ]; then
    export VOICE_MIC_URL="${VOICE_MIC_URL:-$(head -n1 /tmp/myagent_net_mic)}"
fi
# 本机声卡 + 网络麦混音：touch /tmp/myagent_voice_mix 启用
[ -f /tmp/myagent_voice_mix ] && export VOICE_MIC_MIX="${VOICE_MIC_MIX:-1}"
# 客厅萤石（第二路）保持横屏，不旋转
echo 0 > /tmp/myagent_ezviz.rot
exec "$BIN" "$@"
