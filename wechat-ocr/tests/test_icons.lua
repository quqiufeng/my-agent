#!/usr/bin/env luajit
-- WeChat OCR - 全窗口小图标检测
-- 扫描整个微信窗口，标注所有方形暗色块（过滤文字）

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
local ts = os.date("%Y%m%d_%H%M%S")
local outfile = os.getenv("HOME") .. "/wechat_icons_" .. ts .. ".png"
local cmd = string.format("/data/venv/bin/python3 tests/find_icons.py %d %d %d %d '%s' 2>/dev/null", wx, wy, ww, wh, outfile)
os.execute(cmd)

-- 隐藏微信窗口
os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
io.write("  微信已隐藏\n")
