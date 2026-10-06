#!/usr/bin/env bash
# tools/music.sh — WebDAV 无损音乐：搜索 / 随机 / 播放 / 停止（VLC → USB 音响）
# @rule **音乐**：说“放歌/放某某的歌/随机放一首”→ `play <歌手或歌名>`（没说放哪首就 `random`）；“下一首/换一首/切歌”→ `next`；“停/别放了”→ `stop`；“大声点/小声点”→ `volup`/`voldown`。拿不准先 `search <关键词>` 看匹配再 play。
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
