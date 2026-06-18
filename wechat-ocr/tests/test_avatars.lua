#!/usr/bin/env luajit
-- WeChat OCR - 第二列头像检测
-- 用法: luajit tests/test_avatars.lua

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

io.write("=== 第二列头像检测 ===\n\n"); io.flush()

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
io.write(string.format("窗口: %dx%d\n", ww, wh)); io.flush()

local cmd = "/data/venv/bin/python3 tests/find_avatars.py 2>/dev/null"
local f = io.popen(cmd)
local count = tonumber(f:read("*a")) or 0
f:close()

io.write(string.format("头像: %d 个\n", count))
io.write("标注图: ~/wechat_avatars.png\n✅\n"); io.flush()
