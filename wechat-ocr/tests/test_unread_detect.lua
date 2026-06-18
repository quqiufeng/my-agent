#!/usr/bin/env luajit
-- WeChat OCR - 第二列红色未读数检测
-- 用ImageMagick检测第二列中的红色像素区域
-- 用法: luajit tests/test_unread_detect.lua

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

io.write("=== 第二列红色未读数检测 ===\n\n"); io.flush()

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

os.execute("xdotool getactivewindow getwindowgeometry > /tmp/win_ur.txt 2>/dev/null")
local f = io.open("/tmp/win_ur.txt")
local geo = f:read("*a"); f:close()
local _, _, wx = geo:find("Position: (%d+)")
local _, _, wy = geo:find(",(%d+)")
local _, _, ww = geo:find("Geometry: (%d+)")
local _, _, wh = geo:find("x(%d+)")
wx, wy, ww, wh = tonumber(wx), tonumber(wy), tonumber(ww), tonumber(wh)
if not wx then io.write("❌ 获取窗口失败\n"); os.exit(1) end

local col2_w = math.floor(ww * 0.36)
os.execute(string.format("import -window root -crop %dx%d+%d+%d /tmp/sc.png 2>/dev/null",
    col2_w, wh-120, wx+4, wy+60))

-- 用convert找红色区域: R>180 G<100 B<100
local cmd = "convert /tmp/sc.png -channel RGB -separate " ..
    "\\( -clone 0 -threshold 70% \\) " ..
    "\\( -clone 1 -threshold 35% -negate \\) " ..
    "\\( -clone 2 -threshold 35% -negate \\) " ..
    "-delete 0-2 -compose multiply -composite " ..
    "-morphology Erode Square:1 -morphology Dilate Square:2 " ..
    "-trim -format \"%[fx:w*h*mean]\" info:"
local f2 = io.popen(cmd)
local result = f2:read("*a"); f2:close()
local red_count = tonumber(result)

if red_count and red_count > 100 then
    io.write(string.format("  检测到红色像素: %.0f\n", red_count))
else
    io.write("  未检测到红色未读标记\n")
end
io.write("✅\n"); io.flush()
