#!/usr/bin/env luajit
-- WeChat OCR - 搜索联系人测试
-- 流程: 点击搜索框(窗口+180,+50) → 输入关键词 → 回车
-- 用法: luajit tests/test_search.lua [搜索词]

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local keyword = arg[1] or "小王"

io.write("=== 搜索: " .. keyword .. " ===\n"); io.flush()

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 获取窗口位置
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/win_geo2.txt 2>/dev/null")
local f = io.open("/tmp/win_geo2.txt")
local geo = f:read("*a"); f:close()
local _, _, wx = geo:find("Position: (%d+)")
local _, _, wy = geo:find(",(%d+)")
wx, wy = tonumber(wx), tonumber(wy)
if not wx then io.write("❌ 获取窗口失败\n"); os.exit(1) end

-- 搜索框在第二列顶部，相对窗口 (180,50)
local sx = wx + 180
local sy = wy + 50
io.write(string.format("点击搜索框: (%d,%d)\n", sx, sy)); io.flush()
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", sx, sy))
ffi.C.usleep(500000)

-- 输入关键词
io.write("输入: " .. keyword .. "\n"); io.flush()
local f2 = io.open("/tmp/wechat_search.txt", "w")
f2:write(keyword); f2:close()
os.execute("xclip -selection clipboard < /tmp/wechat_search.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(300000)

-- 回车搜索
io.write("搜索...\n"); io.flush()
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)
io.write("✅\n"); io.flush()
