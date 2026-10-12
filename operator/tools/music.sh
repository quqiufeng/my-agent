#!/usr/bin/env bash
# tools/music.sh — 无损音乐：本地(WebDAV)搜索/播放 + 本地没有则在线(flac.music.hi.cn)取 FLAC 播放并存 NAS（VLC → USB 音响）
# @rule **音乐**：说“放歌/放某某的歌/随机放一首”→ `play <歌手或歌名>`（本地库没有会自动**在线取无损 FLAC 播放**并**保存到 NAS**）；“下一首/换一首” → `next`；“停/别放了”→ `stop`；“大声点/小声点”→ `volup`/`voldown`。指定在线源用 `online <关键词> [kuwo|wyy]`。
# @order 7
# 用法:
#   tools/music.sh search <关键词>    # 列出匹配的歌
#   tools/music.sh play <关键词>      # 搜索并播放（随机/第一个匹配）
#   tools/music.sh random             # 随机播放一首
#   tools/music.sh stop               # 停止播放
#
# 凭据：从 ~/.env 载入 WEBDAV_URL / WEBDAV_USER / WEBDAV_PASS / WEBDAV_MUSIC（也可用环境变量覆盖）
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DISPLAY="${DISPLAY:-:0}"

if [ -f "$HOME/.env" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$HOME/.env"
    set +a
fi

exec luajit "$DIR/music.lua" "$@"
