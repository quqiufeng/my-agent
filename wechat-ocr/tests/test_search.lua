#!/usr/bin/env luajit
-- WeChat OCR - 搜索联系人→回车开聊天→输入消息→回车发送
-- 用法:
--   luajit tests/test_search.lua                        搜索"丰"+发送"今天天气真好"
--   luajit tests/test_search.lua [人名] [消息]
--
-- 提示词:
-- 先开启录屏 打开微信在搜索栏 搜索 小王  发送  台风一点都不大 真凉快 小王辛苦了 爱你哦 __来自ai  2秒后 录屏停止  保存到～

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]
math.randomseed(os.time())

local function flush(s) io.write(s); io.flush() end

local keyword = arg[1] or "丰"
local msg = arg[2] or "今天天气真好"

flush(string.format("=== 搜索: %s ===\n", keyword))

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 获取窗口位置
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

-- 输入关键词
os.execute("xdotool type --delay 300 '" .. keyword .. "' 2>/dev/null")
ffi.C.usleep(300000)

-- 回车搜索
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1500000)

-- 再回车打开第一个结果（进入聊天）
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1500000)

-- 输入消息
local safe_msg = msg:gsub("'", "'\\''")
os.execute("xdotool type --delay 80 '" .. safe_msg .. "' 2>/dev/null")
ffi.C.usleep(2000000)

-- 回车发送 + 点发送按钮（双保险）
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(200000)
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + ww - 80, wy + wh - 60))
ffi.C.usleep(500000)
flush(string.format("✅ 已发送: %s\n", msg))
