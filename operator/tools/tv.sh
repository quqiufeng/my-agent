#!/usr/bin/env bash
# @desc 在客厅 Sony 电视上播放 NAS 里的电影/美剧（自写 tvplay，系统硬解；4K/高码率优先无损重封装 MP4：视频原样 copy、音频 AC3，边播边缓存）
# @usage tools/tv.sh play [--remux|--direct|--transcode] [--ss 秒] <片名|文件路径|URL> | transcode [--ss 秒] <片名|路径|URL> | pause | stop | status | shot [输出路径] | diag | install
# @rule 说“电视播放/放个电影/看某剧”→ tools/tv.sh play <名字>；4K/高码率自动无损重封装（视频不转码，只把 DTS/TrueHD 音轨转 AC3），边播边缓存；--direct=原始 MKV；--transcode 才是降 1080p（手动兜底）；暂停→pause；关掉→stop；状态→status/diag
# @order 47
set -uo pipefail

TV="${TV_ADB:-192.168.1.101:5555}"
NAS="${NAS_HOST:-192.168.1.53}"
NAS_PORT="${NAS_PORT:-8099}"
NAS_DATA="${NAS_DATA:-/tmp/zfsv3/sata11/18072858035/data}"
PKG="com.example.tvplay"
APK="/opt/my-agent/agentkit/tvplay/build/tvplay.apk"

HLS_DIR="${TV_HLS_DIR:-/tmp/tvplay_hls}"
REMUX_DIR="${TV_REMUX_DIR:-/tmp/tvplay_remux}"
SRV_PORT="${TV_HLS_PORT:-8097}"
SRV_PID="/tmp/tvplay_server.pid"
HLS_FF_PID="$HLS_DIR/ffmpeg.pid"
REMUX_FF_PID="$REMUX_DIR/ffmpeg.pid"
HOST_IP="${TV_HOST_IP:-}"

adb_tv() { adb -s "$TV" "$@"; }

tv_host() { printf '%s' "${TV%%:*}"; }

host_ip() {
  if [ -n "$HOST_IP" ]; then printf '%s' "$HOST_IP"; return; fi
  ip -4 route get "$(tv_host)" 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'
}

enc_rel() {
  python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
}

find_nas() {
  ssh -n zspace "find '$NAS_DATA' -maxdepth 3 -type f -iname '*${1}*' 2>/dev/null | head -1" 2>/dev/null
}

probe_bitrate() {
  ssh -n zspace "ffprobe -v error -show_entries format=bit_rate -of default=nw=1:nk=1 '$1'" 2>/dev/null \
    | tr -dc '0-9' | head -c 20
}

probe_width() {
  ssh -n zspace "ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 '$1'" 2>/dev/null \
    | tr -dc '0-9' | head -c 6
}

eth_up() {
  adb_tv shell 'ip -4 addr show eth0 2>/dev/null | grep -q "inet "' >/dev/null 2>&1
}

free_port() {
  local p
  for p in $(ss -ltnp 2>/dev/null | sed -n "s/.*:$SRV_PORT .*pid=\([0-9]*\).*/\1/p"); do
    if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'rangeserve.py'; then
      kill "$p" 2>/dev/null || true
    fi
  done
}

stop_media() {
  local f i
  for f in "$HLS_FF_PID" "$REMUX_FF_PID" "$SRV_PID"; do
    if [ -f "$f" ]; then
      kill "$(cat "$f")" 2>/dev/null || true
      rm -f "$f"
    fi
  done
  free_port
  for i in $(seq 1 20); do
    ss -ltn 2>/dev/null | grep -q ":$SRV_PORT " || break
    sleep 0.1
  done
}

start_http_server() {
  local root="$1"
  free_port
  ROOT="$root" PORT="$SRV_PORT" setsid nohup \
    python3 /opt/my-agent/agentkit/rangeserve/rangeserve.py \
    >"$root/server.log" 2>&1 </dev/null &
  echo $! > "$SRV_PID"
  sleep 0.5
  if ! kill -0 "$(cat "$SRV_PID")" 2>/dev/null; then
    echo "HTTP 服务启动失败：" >&2
    tail -10 "$root/server.log" >&2
    return 1
  fi
}

start_hls() {
  local input="$1" ss="${2:-}"
  stop_media
  rm -rf "$HLS_DIR"
  mkdir -p "$HLS_DIR"

  local args=(-hide_banner -loglevel warning -y)
  [ -n "$ss" ] && [ "$ss" != "0" ] && args+=(-ss "$ss")
  args+=(-i "$input"
    -map 0:v:0 -map 0:a:0? -sn
    -vf 'libplacebo=w=1920:h=1080:tonemapping=mobius:colorspace=bt709:color_primaries=bt709:color_trc=bt709:format=yuv420p'
    -c:v h264_nvenc -preset p4 -b:v 5M -maxrate 6M -bufsize 10M -g 48
    -c:a aac -ac 2 -b:a 192k
    -f hls -hls_time 2 -hls_playlist_type event -hls_flags independent_segments
    -hls_segment_filename "$HLS_DIR/seg%05d.ts" "$HLS_DIR/index.m3u8")

  setsid nohup ffmpeg "${args[@]}" >"$HLS_DIR/ffmpeg.log" 2>&1 </dev/null &
  echo $! > "$HLS_FF_PID"
  start_http_server "$HLS_DIR" || { stop_media; return 1; }

  local i n=0
  for i in $(seq 1 40); do
    n=$(find "$HLS_DIR" -maxdepth 1 -name 'seg*.ts' 2>/dev/null | wc -l)
    [ "$n" -ge 6 ] && break
    if ! kill -0 "$(cat "$HLS_FF_PID")" 2>/dev/null; then
      echo "转码失败：" >&2
      tail -20 "$HLS_DIR/ffmpeg.log" >&2
      stop_media
      return 1
    fi
    sleep 0.5
  done
  if [ "$n" -lt 3 ]; then
    echo "转码超时（${n} 段）" >&2
    tail -10 "$HLS_DIR/ffmpeg.log" >&2
    stop_media
    return 1
  fi
  local hip
  hip=$(host_ip)
  [ -n "$hip" ] || { echo "无法确定主机 IP（设 TV_HOST_IP）" >&2; stop_media; return 1; }
  echo "HLS 就绪：$hip:$SRV_PORT/index.m3u8（${n} 段）" >&2
}

start_remux() {
  local input="$1" ss="${2:-}"
  stop_media
  mkdir -p "$REMUX_DIR"

  local key out vcodec
  key=$(printf '%s@%s' "$input" "$ss" | md5sum | cut -c1-16)
  out="$REMUX_DIR/$key.mp4"
  if [ ! -s "$out" ] || [ ! -f "$out.done" ]; then
    rm -f "$out" "$out.done"
    echo "无损重封装中（视频原样 4K，仅音频转 AC3）…" >&2
    vcodec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
      -of default=nw=1:nk=1 "$input" 2>/dev/null | head -1)
    local tag=()
    [ "$vcodec" = "hevc" ] && tag=(-tag:v hvc1)

    local args=(-hide_banner -loglevel warning -y)
    [ -n "$ss" ] && [ "$ss" != "0" ] && args+=(-ss "$ss")
    args+=(-i "$input" -map 0:v:0 -map 0:a:0? -sn
      -c:v copy "${tag[@]}" -c:a ac3 -b:a 640k -ac 6
      -movflags +faststart "$out")

    setsid ffmpeg "${args[@]}" >"$REMUX_DIR/remux.log" 2>&1 </dev/null &
    echo $! > "$REMUX_FF_PID"
    wait "$(cat "$REMUX_FF_PID")"
    local rc=$?
    rm -f "$REMUX_FF_PID"
    if [ "$rc" -ne 0 ] || [ ! -s "$out" ]; then
      echo "remux 失败：" >&2
      tail -20 "$REMUX_DIR/remux.log" >&2
      rm -f "$out"
      return 1
    fi
    touch "$out.done"
  fi
  start_http_server "$REMUX_DIR" || return 1
  echo "$out"
}

launch() {
  local url="$1" engine="${2:-}"
  adb_tv shell am force-stop org.videolan.vlc >/dev/null 2>&1
  if [ -n "$engine" ]; then
    adb_tv shell am start -n "$PKG/.MainActivity" -a android.intent.action.VIEW \
      -e engine "$engine" -d "'$url'" 2>&1 | tail -1
  else
    adb_tv shell am start -n "$PKG/.MainActivity" -a android.intent.action.VIEW \
      -d "'$url'" 2>&1 | tail -1
  fi
}

play() {
  local mode="" ss=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --remux) mode="remux"; shift ;;
      --transcode) mode="transcode"; shift ;;
      --direct) mode="direct"; shift ;;
      --ss) ss="${2:-}"; shift 2 ;;
      --) shift; break ;;
      -*) echo "未知参数: $1" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  local arg="${*:-}"
  [ -n "$arg" ] || { echo "用法: tv.sh play [--remux|--direct|--transcode] [--ss 秒] <片名|路径|URL>" >&2; exit 2; }

  local rel="" url="" br="" vw=""
  if [[ "$arg" =~ ^https?:// ]]; then
    url="$arg"
  else
    rel=$(find_nas "$arg")
    [ -n "$rel" ] || { echo "NAS 里没找到: $arg" >&2; exit 1; }
    local r="${rel#$NAS_DATA/}"
    url="http://$NAS:$NAS_PORT/$(enc_rel "$r")"
    br=$(probe_bitrate "$rel")
    vw=$(probe_width "$rel")
  fi
  echo "$url"

  local use_remux=0 use_hls=0
  if [ "$mode" = "remux" ]; then
    use_remux=1
  elif [ "$mode" = "transcode" ]; then
    use_hls=1
  elif [ "$mode" = "direct" ]; then
    :
  elif [ -n "$rel" ] && ! eth_up; then
    if { [ -n "$vw" ] && [ "$vw" -ge 3000 ]; } \
       || { [ -n "$br" ] && [ "$br" -ge 9000000 ]; }; then
      use_remux=1
    fi
  fi

  local hip out
  hip=$(host_ip)
  if [ "$use_remux" = "1" ]; then
    echo "4K/高码率 → 无损重封装（视频不转码，仅音频 AC3）" >&2
    if out=$(start_remux "$url" "$ss"); then
      [ -n "$hip" ] || { echo "无法确定主机 IP" >&2; exit 1; }
      launch "http://$hip:$SRV_PORT/$(basename "$out")?r=$(date +%s)"
      return
    fi
    echo "remux 失败，回退 1080p 转码" >&2
    use_hls=1
  fi
  if [ "$use_hls" = "1" ]; then
    start_hls "$url" "$ss" || exit 1
    [ -n "$hip" ] || { echo "无法确定主机 IP" >&2; exit 1; }
    launch "http://$hip:$SRV_PORT/index.m3u8?s=$(date +%s)" direct
  else
    stop_media
    launch "$url"
  fi
}

case "${1:-}" in
  play)
    shift
    play "$@"
    ;;
  transcode)
    shift
    SS=""
    if [ "${1:-}" = "--ss" ]; then SS="${2:-}"; shift 2; fi
    ARG="${*:-}"
    [ -n "$ARG" ] || { echo "用法: tv.sh transcode [--ss 秒] <片名|路径|URL>" >&2; exit 2; }
    if [[ "$ARG" =~ ^https?:// ]]; then
      URL="$ARG"
    else
      REL=$(find_nas "$ARG")
      [ -n "$REL" ] || { echo "NAS 里没找到: $ARG" >&2; exit 1; }
      URL="http://$NAS:$NAS_PORT/$(enc_rel "${REL#$NAS_DATA/}")"
    fi
    start_hls "$URL" "$SS" || exit 1
    hip=$(host_ip)
    [ -n "$hip" ] || { echo "无法确定主机 IP" >&2; exit 1; }
    echo "http://$hip:$SRV_PORT/index.m3u8?s=$(date +%s)"
    ;;
  pause)  adb_tv shell input keyevent 85 ;;
  stop)
    stop_media
    adb_tv shell am force-stop "$PKG"
    echo "stopped"
    ;;
  status)
    adb_tv shell "dumpsys window windows | grep mCurrentFocus | head -1"
    if [ -f "$REMUX_FF_PID" ] && kill -0 "$(cat "$REMUX_FF_PID")" 2>/dev/null; then
      echo "remux: processing"
    elif [ -f "$HLS_FF_PID" ] && kill -0 "$(cat "$HLS_FF_PID")" 2>/dev/null; then
      echo "HLS: transcoding"
    elif [ -f "$SRV_PID" ] && kill -0 "$(cat "$SRV_PID")" 2>/dev/null; then
      echo "server: ready"
    else
      echo "server: off"
    fi
    ;;
  diag)
    echo "TV: $TV"
    adb_tv shell 'ip -4 addr show eth0 2>/dev/null | grep inet; ip -4 addr show wlan0 2>/dev/null | grep inet'
    adb_tv shell "dumpsys wifi | grep -m1 -oE 'SSID: [^,]+|RSSI: -?[0-9]+|Link speed: [0-9]+Mbps'" 2>/dev/null | tr '\n' ' '; echo
    if [ -f "$SRV_PID" ] && kill -0 "$(cat "$SRV_PID")" 2>/dev/null; then
      echo "server: ready"
    else
      echo "server: off"
    fi
    ;;
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
