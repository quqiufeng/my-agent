#!/usr/bin/env luajit
-- 搜索 → 截图发送（使用缓存坐标）
-- 流程: 搜索"丰" → 打开聊天 → 截图 → 发送
-- 用法: luajit tests/test_screenshot.lua [关键词]

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;/opt/my-agent/wechat-ocr/lua/?.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local function flush(s) io.write(s); io.flush() end

local keyword = arg[1] or "丰"
flush(string.format("=== 搜索「%s」→ 截图发送 ===\n\n", keyword))

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 获取窗口位置
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/wx_geo.txt 2>/dev/null")
local f = io.open("/tmp/wx_geo.txt")
local geo = f:read("*a"); f:close()
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
if not wx then flush("❌ 获取窗口失败\n"); os.exit(1) end

-- 加载缓存坐标
local cjson = require("cjson")
local cache_f = io.open(os.getenv("HOME") .. "/.wechat_icons.json")
if not cache_f then flush("❌ 缓存不存在，先运行 calibrate_icons.lua\n"); os.exit(1) end
local cache = cjson.decode(cache_f:read("*a"))
cache_f:close()

-- [1/4] 点搜索框
flush("[1/4] 搜索「" .. keyword .. "」...\n")
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + 180, wy + 50))
ffi.C.usleep(500000)

-- 输入关键词
os.execute("xdotool type --delay 300 '" .. keyword .. "' 2>/dev/null")
ffi.C.usleep(300000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1500000)

-- 回车打开第一个结果聊天
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1500000)

-- 在工具栏中找 Scissors（截图）
local scissors = nil
for _, icon in ipairs(cache.toolbar) do
    if icon.name == "Scissors" then
        scissors = icon
        break
    end
end
if not scissors then flush("❌ 缓存中未找到 Scissors\n"); os.exit(1) end

local cx = wx + scissors.rel_x
local cy = wy + scissors.rel_y
flush(string.format("Scissors → (%d,%d)\n", cx, cy))

-- [2/4] 点击截图图标进入截图模式
flush("[2/4] 进入截图模式...\n")
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", cx, cy))
ffi.C.usleep(800000)

-- [3/4] 框选全屏
flush("[3/4] 框选全屏...\n")
os.execute("xdotool mousemove 0 0 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool mousedown 1 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool mousemove 2560 1440 2>/dev/null")
ffi.C.usleep(300000)
os.execute("xdotool mouseup 1 2>/dev/null")
ffi.C.usleep(500000)

-- [4/4] 双击确认 + 回车发送
flush("[4/4] 确认并发送...\n")
os.execute("xdotool mousemove 1280 720 2>/dev/null")
ffi.C.usleep(200000)
os.execute("xdotool click 1 2>/dev/null")
ffi.C.usleep(200000)
os.execute("xdotool click 1 2>/dev/null")
ffi.C.usleep(1000000)

os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)

flush("✅ 截图已发送\n")
