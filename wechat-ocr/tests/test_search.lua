#!/usr/bin/env luajit
-- WeChat OCR - 搜索联系人 → 点第一个结果 → 发送消息
-- 用法:
--   luajit tests/test_search.lua [搜索词]             只搜索
--   luajit tests/test_search.lua [搜索词] [消息]      搜索+点结果+发消息

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]

local keyword = arg[1] or "小王"
local msg = arg[2]  -- 可选：要发送的消息

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
local sx, sy = wx + 180, wy + 50
flush(string.format("点击搜索框: (%d,%d)\n", sx, sy))
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", sx, sy))
ffi.C.usleep(500000)

-- 输入关键词
flush("输入: " .. keyword .. "\n")
local f2 = io.open("/tmp/wx_s.txt", "w"); f2:write(keyword); f2:close()
os.execute("xclip -selection clipboard < /tmp/wx_s.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(300000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)
flush("✅ 搜索完成\n")

-- 如果没有消息参数，到这里结束
if not msg then os.exit(0) end

-- 点第一个搜索结果
flush("点第一个结果...\n")
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + 180, wy + 90))
ffi.C.usleep(1500000)

-- 发送消息（移植自 wechat_robot.lua 的 send 功能）
flush("发送: " .. msg .. "\n")
-- 点输入框（第三列底部）
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + ww - 200, wy + wh - 80))
ffi.C.usleep(500000)
-- 剪贴板粘贴
local f3 = io.open("/tmp/wx_msg.txt", "w"); f3:write(msg); f3:close()
os.execute("xclip -selection clipboard < /tmp/wx_msg.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(500000)
-- 回车发送
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)
flush("✅ 已发送\n")
