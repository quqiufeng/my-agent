#!/usr/bin/env bash
# tools/wechat_send_file.sh — 发送文件/图片到微信
# 用法: wechat_send_file.sh <本地路径|http(s)://URL> [--to 联系人]
#   URL（如 WebDAV 歌曲）会先用 curl 下载到 /tmp 再发送（用 ~/.env 的 WEBDAV 凭据）。
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

FILE="${1:-}"
if [ -z "$FILE" ]; then echo "用法: wechat_send_file.sh <文件路径|URL> [--to 联系人]" >&2; exit 2; fi
shift || true

TO=""
if [ "${1:-}" = "--to" ]; then TO="${2:-}"; fi

# URL → 先下载到本地
if [[ "$FILE" =~ ^https?:// ]]; then
    [ -f "$HOME/.env" ] && { set -a; . "$HOME/.env"; set +a; }
    raw="$(basename "${FILE%%\?*}")"
    dec="$(printf '%b' "${raw//%/\\x}")"
    out="/tmp/myagent_dl_$(date +%s)_${dec}"
    if ! curl -fsSL -m 300 -u "${WEBDAV_USER:-}:${WEBDAV_PASS:-}" -o "$out" "$FILE"; then
        echo "下载失败: $FILE" >&2; exit 1
    fi
    FILE="$out"
fi

if [ ! -f "$FILE" ]; then echo "文件不存在: $FILE" >&2; exit 2; fi

export LD_LIBRARY_PATH="/opt/my-agent/wechat-ocr/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:${LD_LIBRARY_PATH:-}"
export LUA_PATH="/opt/my-agent/wechat-ocr/?.lua;/opt/my-agent/wechat-ocr/lua/?.lua;/opt/my-agent/wechat-ocr/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;"
export DISPLAY="${DISPLAY:-:0}"

WECHAT_TO="$TO" exec luajit "$DIR/wechat_send_file.lua" "$FILE"
