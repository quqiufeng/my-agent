#!/usr/bin/env luajit
-- WeChat OCR - 全窗口小图标检测
-- 扫描整个微信窗口，标注所有小方形暗色块

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))

io.write(string.format("窗口: (%d,%d) %dx%d\n", wx, wy, ww, wh))

local cmd = string.format(
    "/data/venv/bin/python3 tests/find_all_icons.py %d %d %d %d 2>/dev/null",
    wx, wy, ww, wh)
os.execute(cmd)
io.write("标记图: ~/wechat_all_icons_full.png\n")
