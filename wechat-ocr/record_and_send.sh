#!/bin/bash
DIR="/opt/my-agent/wechat-ocr"
OUTPUT="/tmp/wechat_process.mp4"

echo "=== 开始录屏 15秒 ==="
ffmpeg -y -f x11grab -r 10 -s 2560x1440 -i :0.0 \
  -vcodec libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
  -t 15 "$OUTPUT" &
FFPID=$!
sleep 1

echo "=== 操作微信 ==="
LD_LIBRARY_PATH="$DIR/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib" \
LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;" \
LUA_CPATH="/usr/local/lualib/?.so;;" \
/usr/local/bin/luajit "$DIR/run_ops.lua"

echo "=== 等待录屏结束 ==="
wait $FFPID 2>/dev/null || true

echo "=== 播放录像 ==="
ls -lh "$OUTPUT"
vlc "$OUTPUT" 2>/dev/null &
