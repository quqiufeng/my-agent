#!/usr/bin/env luajit
-- WeChat OCR - 第二列头像检测
-- 扫描左侧区域，找彩色方块（头像约75x75px）
-- 用法: luajit tests/test_avatars.lua

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

io.write("=== 第二列头像检测 ===\n\n"); io.flush()

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

os.execute("xdotool getactivewindow getwindowgeometry > /tmp/av7.txt 2>/dev/null")
local f = io.open("/tmp/av7.txt")
local geo = f:read("*a"); f:close()
local _, _, ww = geo:find("Geometry: (%d+)")
local _, _, wh = geo:find("x(%d+)")
ww, wh = tonumber(ww), tonumber(wh)
io.write(string.format("窗口: %dx%d\n", ww, wh)); io.flush()

-- 截微信窗口
os.execute("import -window $(xdotool search --name 微信 | head -1) /tmp/av_win.png 2>/dev/null")

-- 裁左侧200px（头像在左侧100-180px处）
os.execute("convert /tmp/av_win.png -crop 200x"..(wh-60).."+0+50 /tmp/av_left.png 2>/dev/null")

-- 每65px采样（chat间距）
local avatars = {}
for y = 20, wh-100, 65 do
    local cmd = string.format(
        "convert /tmp/av_left.png -crop 1x1+100+%d -format \"%%[fx:r*255],%%[fx:g*255],%%[fx:b*255]\" info: 2>/dev/null", y)
    local f2 = io.popen(cmd)
    local rgb = f2:read("*a"); f2:close()
    local r, g, b = rgb:match("([%d.]+),([%d.]+),([%d.]+)")
    if r and g and b then
        local rn, gn, bn = math.floor(tonumber(r)+0.5), math.floor(tonumber(g)+0.5), math.floor(tonumber(b)+0.5)
        local diff = math.max(rn,gn,bn) - math.min(rn,gn,bn)
        if diff > 15 then
            table.insert(avatars, {x=65, y=y-20, w=75, h=75})
        end
    end
end

io.write(string.format("头像: %d 个\n", #avatars))

-- 出图
local f3 = io.open("/tmp/av_data3.json","w")
f3:write("{\"avatars\":[")
for i, a in ipairs(avatars) do
    if i > 1 then f3:write(",") end
    f3:write(string.format('{"x":%d,"y":%d,"w":%d,"h":%d}', a.x, a.y, a.w, a.h))
end
f3:write("]}"); f3:close()

os.execute("/data/venv/bin/python3 tests/mark_avatars.py 2>/dev/null")
