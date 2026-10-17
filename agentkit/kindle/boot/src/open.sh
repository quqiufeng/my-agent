#!/bin/sh
# 打开一本书：交接给 kindlepdfviewer 独占屏幕，阅读退出后重启书架 UI
pkill -9 lvgui 2>/dev/null
sleep 1
echo 14 0 > /proc/eink_fb/update_display 2>/dev/null
cd /mnt/us/kindlepdfviewer && sh kpdf.sh "$1" >/tmp/kpdf.log 2>&1
echo 14 2 > /proc/eink_fb/update_display 2>/dev/null
/sbin/start-stop-daemon -S -b -x /mnt/us/lvgui
