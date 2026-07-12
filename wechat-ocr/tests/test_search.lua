#!/usr/bin/env luajit
-- WeChat OCR - 搜索"丰"→回车→逐字输入"今天天气真好啊"→回车
-- 用法: luajit tests/test_search.lua

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]
math.randomseed(os.time())

local function flush(s) io.write(s); io.flush() end

-- UTF-8 逐字拆分
local function utf8_chars(s)
    local chars = {}
    local i = 1
    while i <= #s do
        local b = s:byte(i)
        local len
        if b < 128 then len = 1
        elseif b < 224 then len = 2
        elseif b < 240 then len = 3
        else len = 4 end
        chars[#chars+1] = s:sub(i, i + len - 1)
        i = i + len
    end
    return chars
end

local msg = "今天天气真好啊"
local chars = utf8_chars(msg)

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

-- 粘贴"丰"到搜索框
local f2 = io.open("/tmp/wx_search.txt", "w"); f2:write("丰"); f2:close()
os.execute("xclip -selection clipboard < /tmp/wx_search.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(200000)

-- 回车搜索
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)

-- 逐字输入（模拟真人打字，每字间隔随机延迟）
flush("输入: " .. msg .. " (" .. #chars .. "字)\n")
for _, ch in ipairs(chars) do
    os.execute("xdotool type '" .. ch .. "' 2>/dev/null")
    ffi.C.usleep(80000 + math.random(0, 120000))
end
ffi.C.usleep(200000)

-- 回车发送
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(500000)
flush("✅ 完成\n")
