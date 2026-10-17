#!/bin/sh
# 停 Amazon 框架 + 设横屏 + 常驻运行 agent UI
echo 14 0 > /proc/eink_fb/update_display 2>/dev/null
killall -STOP cvm 2>/dev/null
if ! ps | grep -q "[l]vgui"; then
  /sbin/start-stop-daemon -S -b -x /mnt/us/lvgui
fi
echo "ui started (landscape, cvm paused)"
