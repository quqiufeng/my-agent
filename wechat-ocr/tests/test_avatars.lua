#!/usr/bin/env luajit
-- WeChat OCR - 第二列头像检测
-- 扫描颜色差异定位彩色方块
-- 用法: luajit tests/test_avatars.lua

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

io.write("=== 第二列头像检测 ===\n\n"); io.flush()

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
io.write(string.format("窗口: %dx%d\n\n", ww, wh)); io.flush()

os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx+40, wy+110))
ffi.C.usleep(1000000)

os.execute(string.format("import -window $(xdotool search --name 微信 | head -1) /tmp/av_final2.png 2>/dev/null"))
os.execute(string.format("convert /tmp/av_final2.png -crop 250x%d+0+50 /tmp/av_left_f2.png 2>/dev/null", wh-60))

-- 扫描x=100处颜色差异
local rows = {}
for y = 10, wh-100, 2 do
    local cmd = string.format("convert /tmp/av_left_f2.png -crop 1x1+100+%d -format \"%%[fx:r*255],%%[fx:g*255],%%[fx:b*255]\" info: 2>/dev/null", y)
    local f2 = io.popen(cmd)
    local rgb = f2:read("*a"); f2:close()
    local r, g, b = rgb:match("([%d.]+),([%d.]+),([%d.]+)")
    if r and g and b then
        local diff = math.abs(tonumber(r)-tonumber(g)) + math.abs(tonumber(g)-tonumber(b))
        if diff > 6 then table.insert(rows, y+50) end
    end
end

local groups, cur = {}, {}
for _, y in ipairs(rows) do
    if #cur == 0 or y - cur[#cur] < 8 then table.insert(cur, y)
    else
        if #cur > 15 then table.insert(groups, cur) end
        cur = {y}
    end
end
if #cur > 15 then table.insert(groups, cur) end

local avatars = {}
for i, g in ipairs(groups) do
    local mid = g[math.floor(#g/2)]
    table.insert(avatars, {x=90, y=mid-50, w=60, h=100})
end

io.write(string.format("头像: %d 个\n", #avatars))
for i, a in ipairs(avatars) do
    io.write(string.format("  #%d: (%d,%d) 75x75\n", i, a.x, a.y))
end

-- 出图
local f3 = io.open("/tmp/av_f2.json","w")
f3:write("{\"avatars\":[")
for i, a in ipairs(avatars) do
    if i > 1 then f3:write(",") end
    f3:write(string.format('{"x":%d,"y":%d,"w":%d,"h":%d}', a.x, a.y, a.w, a.h))
end
f3:write("]}"); f3:close()

os.execute("/data/venv/bin/python3 tests/mark_avatars.py 2>/dev/null")
