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

-- 每个聊天项大约70px高，头像约40x40px
-- 红色标记在头像右上角，大约在 (item_x+30, item_y+5) 附近
-- 垂直扫描每70px检查一个聊天项的头像右上角

-- 用ImageMagick的connected-components找红色斑点
-- 条件: R>180 G<90 B<90，面积40-400px，高宽>5
local check = "convert /tmp/sc.png -channel RGB -separate " ..
    "\\( -clone 0 -threshold 70%% \\) " ..
    "\\( -clone 1 -threshold 30%% -negate \\) " ..
    "\\( -clone 2 -threshold 30%% -negate \\) " ..
    "-delete 0-2 -compose multiply -composite " ..
    "-morphology Close Diamond:1 " ..
    "-define connected-components:area-threshold=40 " ..
    "-define connected-components:mean-color=true " ..
    "-connected-components 4 -auto-level -trim " ..
    "-format \"%%[width]x%%[height]+%%[page.x]+%%[page.y]\\n\" info:"

local f2 = io.popen(check)
local result = f2:read("*a"); f2:close()

local count = 0
for line in result:gmatch("[^\n]+") do
    local w, h, x, y = line:match("(%d+)x(%d+)+(%d+)+(%d+)")
    if w and h then
        local wn, hn = tonumber(w), tonumber(h)
        if wn and hn and wn > 5 and hn > 5 and wn < 60 and hn < 60 then
            count = count + 1
            io.write(string.format("  🔴 红色斑#%d: (%d,%d) %dx%d\n", count, wx+4+tonumber(x), wy+60+tonumber(y), wn, hn))
        end
    end
end

if count == 0 then
    io.write("  未检测到红色未读标记\n")
else
    io.write(string.format("\n共 %d 个红色未读标记\n", count))
end
io.write("✅\n"); io.flush()
