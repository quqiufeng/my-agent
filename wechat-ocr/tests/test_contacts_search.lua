#!/usr/bin/env luajit
-- WeChat OCR - 通讯录搜索测试
-- 流程: 点第一列第2个图标(通讯录) → 搜索框输入关键词 → 回车
-- 用法: luajit tests/test_contacts_search.lua [搜索词]

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local keyword = arg[1] or "小王"

io.write("=== 通讯录搜索: " .. keyword .. " ===\n"); io.flush()

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 获取窗口位置
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/win_geo4.txt 2>/dev/null")
local f = io.open("/tmp/win_geo4.txt")
local geo = f:read("*a"); f:close()
local _, _, wx = geo:find("Position: (%d+)")
local _, _, wy = geo:find(",(%d+)")
wx, wy = tonumber(wx), tonumber(wy)
if not wx then io.write("❌ 获取窗口失败\n"); os.exit(1) end

-- 第2个图标：通讯录
local icon_x = wx + 40
local icon_y = wy + 110 + 60  -- 聊天 + 60px
io.write(string.format("点通讯录: (%d,%d)\n", icon_x, icon_y)); io.flush()
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", icon_x, icon_y))
ffi.C.usleep(800000)

-- 搜索框位置
local sx = wx + 160
local sy = wy + 50
io.write(string.format("点搜索框: (%d,%d)\n", sx, sy)); io.flush()
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", sx, sy))
ffi.C.usleep(500000)

-- 粘贴关键词
io.write("搜索: " .. keyword .. "\n"); io.flush()
os.execute(string.format("echo -n '%s' | xclip -selection clipboard 2>/dev/null", keyword))
ffi.C.usleep(200000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(500000)

-- 回车
io.write("回车\n"); io.flush()
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)
io.write("✅\n"); io.flush()
