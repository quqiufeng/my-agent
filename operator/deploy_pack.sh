#!/usr/bin/env bash
# deploy_pack.sh — 校验/打包 my-agent 部署所需资源
#   （出图相关已在基础镜像里，不含在本清单）
# 用法:
#   deploy_pack.sh --check            逐项校验（目录/文件/命令），打印缺失
#   deploy_pack.sh --pack [out.tgz]   打包核心资源（保留绝对路径，默认 /tmp/myagent-core.tgz）
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

# ── 需搬运的目录（绝对路径） ──────────────────────────────────
DIRS=(
  "$ROOT/operator/.opencode/node_modules"
  "/opt/SenseVoice.cpp"
  "/opt/sherpa-onnx"
  "/opt/cosyvoice.cpp/build/bin"
  "/opt/cosyvoice.cpp/build/lib"
  "/data/models/kokoro-multi-lang-v1_0"
  "/data/venv/onnxruntime-linux-x64-gpu-1.26.0"
  "$HOME/.myagent_voices"
)
# ── 需搬运的单文件 ────────────────────────────────────────────
FILES=(
  "$HOME/.env"
  "$ROOT/wechat-ocr/lib/libwechat_ocr_core.so"
  "$ROOT/wechat-ocr/models/ch_PP-OCRv4_det_infer.onnx"
  "$ROOT/wechat-ocr/models/ch_PP-OCRv4_rec_infer.onnx"
  "$ROOT/joycaption-wrapper/libjoycaption.so"
  "$ROOT/voice/listen/listen"
  "$ROOT/voice/orb/orb"
  "$ROOT/voice/app/app"
  "$ROOT/voice/camera/camera"
  "/data/models/sense-voice-small-q4_k.gguf"
  "/data/models/cosyvoice3-gguf/CosyVoice3-2512_F16.gguf"
  "/data/models/Fun-CosyVoice3-0.5B/speech_tokenizer_v3.onnx"
  "/data/models/Fun-CosyVoice3-0.5B/campplus.onnx"
)
# ── 系统命令 ──────────────────────────────────────────────────
CMDS=(opencode node npx luajit tmux ffmpeg curl adb google-chrome)

check() {
  local miss=0 p sz c
  echo "== 目录 =="
  for p in "${DIRS[@]}"; do
    sz="$(du -sh "$p" 2>/dev/null | cut -f1)"
    if [ -e "$p" ]; then printf '  [ok]   %-58s %s\n' "$p" "$sz"; else printf '  [MISS] %s\n' "$p"; miss=$((miss+1)); fi
  done
  echo "== 文件 =="
  for p in "${FILES[@]}"; do
    sz="$(du -h "$p" 2>/dev/null | cut -f1)"
    if [ -e "$p" ]; then printf '  [ok]   %-58s %s\n' "$p" "$sz"; else printf '  [MISS] %s\n' "$p"; miss=$((miss+1)); fi
  done
  echo "== 命令 =="
  for c in "${CMDS[@]}"; do
    if command -v "$c" >/dev/null 2>&1; then printf '  [ok]   %-12s %s\n' "$c" "$(command -v "$c")"; else printf '  [MISS] %s\n' "$c"; miss=$((miss+1)); fi
  done
  echo
  echo "缺失/未找到：$miss 项"
}

pack() {
  local out="${1:-/tmp/myagent-core.tgz}"
  local list; list="$(mktemp /tmp/dpk_list.XXXXXX)"; local p n=0
  for p in "${DIRS[@]}" "${FILES[@]}"; do
    if [ -e "$p" ]; then printf '%s\0' "$p"; n=$((n+1)); else echo "跳过(不存在): $p" >&2; fi
  done > "$list"
  echo "打包 $n 项 -> $out"
  tar czf "$out" -P --null -T "$list" || { echo "打包失败" >&2; rm -f "$list"; return 1; }
  rm -f "$list"
  echo "完成：$(du -h "$out" | cut -f1)"
  echo
  echo "传到目标机并还原到相同绝对路径："
  echo "  scp $out <user>@<host>:/tmp/"
  echo "  ssh <user>@<host> 'sudo tar xzf /tmp/$(basename "$out") -C / -P'"
}

case "${1:-}" in
  --check) check ;;
  --pack)  pack "${2:-/tmp/myagent-core.tgz}" ;;
  *) check; echo; echo "用法: deploy_pack.sh --check | --pack [out.tgz]" ;;
esac
