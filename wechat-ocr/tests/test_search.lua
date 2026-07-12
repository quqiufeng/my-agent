#!/usr/bin/env luajit
-- WeChat OCR - 搜索联系人→回车开聊天→输入消息→回车发送
-- 用法:
--   luajit tests/test_search.lua                        默认搜索"丰"+发送"今天天气真好"
--   luajit tests/test_search.lua [人名]                 只搜索
--   luajit tests/test_search.lua [人名] [消息]          搜索+输入消息+发送

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]
math.randomseed(os.time())

local function flush(s) io.write(s); io.flush() end

local keyword = arg[1] or "丰"
local msg
if #arg == 0 then
    msg = "今天天气真好"
elseif #arg >= 2 then
    msg = arg[2]
end

flush(string.format("=== 搜索: %s ===\n", keyword))

-- 获取微信窗口ID
local win_pipe = io.popen("xdotool search --name 微信 2>/dev/null | head -1")
local wxwin = win_pipe:read("*a"):match("%d+")
win_pipe:close()
if not wxwin then flush("❌ 找不到微信窗口\n"); os.exit(1) end

-- 激活微信
os.execute("xdotool windowactivate " .. wxwin .. " 2>/dev/null")
ffi.C.usleep(500000)

-- 获取窗口位置
local geo_pipe = io.popen("xdotool getwindowgeometry " .. wxwin .. " 2>/dev/null")
local geo = geo_pipe:read("*a"); geo_pipe:close()
local _, _, wx = geo:find("Position: (%d+)")
local _, _, wy = geo:find(",(%d+)")
wx, wy = tonumber(wx), tonumber(wy)
if not wx then flush("❌ 获取窗口位置失败\n"); os.exit(1) end

local function key_enter()
    os.execute("xdotool key --window " .. wxwin .. " Return 2>/dev/null")
end

-- 点搜索框
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + 180, wy + 50))
ffi.C.usleep(500000)

-- 输入关键词
os.execute(string.format("xdotool type --delay 300 '%s' 2>/dev/null", keyword))
ffi.C.usleep(300000)

-- 回车搜索
key_enter()
ffi.C.usleep(1500000)

-- 再回车打开第一个结果（进入聊天）
key_enter()
ffi.C.usleep(1500000)

if msg then
    -- 输入消息（每键间隔150ms，模拟真人）
    os.execute(string.format("xdotool type --delay 150 '%s' 2>/dev/null", msg))
    ffi.C.usleep(300000)

    -- 回车发送
    key_enter()
    ffi.C.usleep(500000)
    flush(string.format("✅ 已发送: %s\n", msg))
else
    flush("✅ 搜索完成\n")
end
