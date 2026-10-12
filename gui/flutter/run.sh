#!/usr/bin/env bash
# run.sh — 启动 my-agent 桌面界面（未构建会先构建）
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BUNDLE="$HERE/build/linux/x64/release/bundle"; BIN="$BUNDLE/myagent_ui"
# 运行期库：语音/OCR/C 依赖（后续 FFI 用）
export LD_LIBRARY_PATH="$ROOT/voice/libs:$ROOT/libs:$ROOT/agentkit/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:${LD_LIBRARY_PATH:-}"
[ -x "$BIN" ] || { echo "尚未构建，编译中 ..."; "$HERE/build.sh" || { echo "构建失败" >&2; exit 1; }; }
exec "$BIN" "$@"
