#!/usr/bin/env bash
# @desc 在客厅 Sony 电视上播放 NAS 里的电影/美剧（自写 tvplay，系统硬解；NAS 提供带 Range 的 HTTP 文件服务）
# @usage tools/tv.sh play <片名|文件路径|URL> | pause | stop | status | shot [输出路径] | install
# @rule 说“电视播放/放个电影/看某剧”→ tools/tv.sh play <名字>；暂停→pause；关掉→stop；看看电视在放什么→status/shot
# @order 47
set -uo pipefail

TV="${TV_ADB:-192.168.1.101:5555}"
NAS="${NAS_HOST:-192.168.1.53}"
NAS_PORT="${NAS_PORT:-8099}"
NAS_DATA="${NAS_DATA:-/tmp/zfsv3/sata11/18072858035/data}"
PKG="com.example.tvplay"
APK="/opt/my-agent/agentkit/tvplay/build/tvplay.apk"

adb_tv() { adb -s "$TV" "$@"; }

case "${1:-}" in
  play)
    shift
    ARG="${*:-}"
    [ -n "$ARG" ] || { echo "用法: tv.sh play <片名|路径|URL>" >&2; exit 2; }
    if [[ "$ARG" =~ ^https?:// ]]; then
      URL="$ARG"
    else
      # 在 NAS 数据目录里找文件（模糊匹配）
      REL=$(ssh -n zspace "find '$NAS_DATA' -maxdepth 3 -type f -iname '*${ARG}*' 2>/dev/null | head -1" 2>/dev/null)
      [ -n "$REL" ] || { echo "NAS 里没找到: $ARG" >&2; exit 1; }
      REL="${REL#$NAS_DATA/}"
      URL=$(python3 - "$NAS" "$NAS_PORT" "$REL" <<'PY'
import sys, urllib.parse
host, port, path = sys.argv[1], sys.argv[2], sys.argv[3]
print("http://%s:%s/%s" % (host, port, urllib.parse.quote(path)))
PY
)
    fi
    echo "$URL"
    adb_tv shell am force-stop org.videolan.vlc >/dev/null 2>&1
    adb_tv shell am start -n "$PKG/.MainActivity" -a android.intent.action.VIEW -d "'$URL'" 2>&1 | tail -1
    ;;
  pause)  adb_tv shell input keyevent 85 ;;
  stop)   adb_tv shell am force-stop "$PKG" ;;
  status) adb_tv shell "dumpsys window windows | grep mCurrentFocus | head -1" ;;
  shot)
    OUT="${2:-/tmp/myagent_tv.jpg}"
    adb_tv exec-out screencap -p > "$OUT"
    echo "$OUT"
    ;;
  install)
    [ -f "$APK" ] || bash /opt/my-agent/agentkit/tvplay/build.sh
    adb_tv install -r "$APK" 2>&1 | tail -1
    ;;
  *) sed -n '2,6p' "$0"; exit 2 ;;
esac
