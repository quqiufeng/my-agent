#!/usr/bin/env luajit
-- WeChat OCR - 搜索"丰"→回车→输入"1"→回车
-- 用法: luajit tests/test_search.lua

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]
math.randomseed(os.time())

local function flush(s) io.write(s); io.flush() end

flush("=== 搜索: 丰 ===\n")

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 点搜索框
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/wx_geo.txt 2>/dev/null")
local f = io.open("/tmp/wx_geo.txt")
local geo = f:read("*a"); f:close()
local _, _, wx = geo:find("Position: (%d+)")
local _, _, wy = geo:find(",(%d+)")
wx, wy = tonumber(wx), tonumber(wy)
if not wx then flush("❌ 获取窗口失败\n"); os.exit(1) end

os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + 180, wy + 50))
ffi.C.usleep(500000)

-- type "丰"（直接用键盘打字，不用粘贴）
os.execute("xdotool type '丰' 2>/dev/null")
ffi.C.usleep(200000)

-- 回车搜索
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)

-- type "1"
os.execute("xdotool type '1' 2>/dev/null")
ffi.C.usleep(200000)

-- 回车发送
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(500000)
flush("✅ 完成\n")
