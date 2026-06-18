#!/usr/bin/env luajit
-- WeChat OCR - 第一列图标依次点击
-- 从顶部开始，依次点击左侧图标栏的每个图标
-- 用法: luajit tests/test_first_column.lua

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

io.write("=== 第一列图标依次点击 ===\n\n"); io.flush()

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 获取窗口位置
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/win_geo3.txt 2>/dev/null")
local f = io.open("/tmp/win_geo3.txt")
local geo = f:read("*a"); f:close()
local _, _, wx = geo:find("Position: (%d+)")
local _, _, wy = geo:find(",(%d+)")
local _, _, ww = geo:find("Geometry: (%d+)")
wx, wy = tonumber(wx), tonumber(wy)
if not wx then io.write("❌ 获取窗口失败\n"); os.exit(1) end

-- 第一列图标位置
local icon_x = wx + 40        -- 靠左边40px
local start_y = wy + 110      -- 顶部往下110px
local gap = 60                -- 每次往下移动60px

-- 图标标签（仅供显示）
local labels = {"1:聊天", "2:通讯录", "3:收藏", "4:朋友圈", "5:小程序", "6:更多"}

io.write(string.format("窗口: (%d,%d)\n", wx, wy))
io.write(string.format("图标列: x=%d 从y=%d 间距%dpx\n\n", icon_x, start_y, gap)); io.flush()

for i = 1, 6 do
    local iy = start_y + (i - 1) * gap
    local label = labels[i] or ("图标" .. i)
    
    io.write(string.format("[%d/6] %s (%d,%d)\n", i, label, icon_x, iy)); io.flush()
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", icon_x, iy))
    ffi.C.usleep(800000)
end

io.write("\n✅ 完成\n"); io.flush()
