#!/usr/bin/env luajit
-- WeChat OCR - 搜索联系人 → 点第一个结果 → 逐字发送
-- 用法:
--   luajit tests/test_search.lua [搜索词]             只搜索
--   luajit tests/test_search.lua [搜索词] [消息]      搜索+结果+逐字发送

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]
math.randomseed(os.time())

local keyword = arg[1] or "小王"
local msg = arg[2]

local function flush(s) io.write(s); io.flush() end

flush("=== 搜索: " .. keyword .. " ===\n")

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/wx_geo.txt 2>/dev/null")
local f = io.open("/tmp/wx_geo.txt")
local geo = f:read("*a"); f:close()
local _, _, wx = geo:find("Position: (%d+)")
local _, _, wy = geo:find(",(%d+)")
local _, _, ww = geo:find("Geometry: (%d+)")
local _, _, wh = geo:find("x(%d+)")
wx, wy, ww, wh = tonumber(wx), tonumber(wy), tonumber(ww), tonumber(wh)
if not wx then flush("❌ 获取窗口失败\n"); os.exit(1) end

-- 点搜索框
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + 180, wy + 50))
ffi.C.usleep(500000)

-- 输入关键词 + 回车搜索
local f2 = io.open("/tmp/wx_s.txt", "w"); f2:write(keyword); f2:close()
os.execute("xclip -selection clipboard < /tmp/wx_s.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(300000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)
flush("✅ 搜索完成\n")

if not msg then os.exit(0) end

-- 点第一个结果（打开聊天）
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + 180, wy + 90))
ffi.C.usleep(1500000)

-- 逐字粘贴（输入框已聚焦）
flush("发送: " .. msg .. "\n")
for i = 1, #msg do
    local ch = msg:sub(i, i)
    local f3 = io.open("/tmp/wx_char.txt", "w"); f3:write(ch); f3:close()
    os.execute("xclip -selection clipboard < /tmp/wx_char.txt 2>/dev/null")
    ffi.C.usleep(50000 + math.random(0, 80000))
    os.execute("xdotool key ctrl+v 2>/dev/null")
    ffi.C.usleep(100000 + math.random(0, 150000))
end
ffi.C.usleep(300000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)
flush("✅ 已发送\n")
