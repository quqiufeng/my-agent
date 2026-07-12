#!/usr/bin/env luajit
-- Google AI 搜索 → 截图 → 微信发送
-- 流程: Chrome AI 搜索 → 截图到剪贴板 → 微信搜索 "丰" → 粘贴发送
-- 用法: luajit tests/google_ai_test.lua

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local function flush(s) io.write(s); io.flush() end
flush("=== Google AI → 微信发送 ===\n\n")

-- [1/5] Chrome AI 搜索
flush("[1/5] Chrome AI 搜索...\n")
os.execute("xdotool search --name 'Google Chrome' windowactivate --sync 2>/dev/null")
ffi.C.usleep(500000)

-- 获取 Chrome 窗口位置（截图用）
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/chrome_geo.txt 2>/dev/null")
local f = io.open("/tmp/chrome_geo.txt")
local geo = f:read("*a"); f:close()
local cx = tonumber(geo:match("Position: (%d+)"))
local cy = tonumber(geo:match(",(%d+)"))
local cw = tonumber(geo:match("Geometry: (%d+)"))
local ch = tonumber(geo:match("x(%d+)"))
flush(string.format("  Chrome: (%d,%d) %dx%d\n", cx, cy, cw, ch))

os.execute("xdotool key ctrl+t 2>/dev/null")
ffi.C.usleep(500000)
os.execute("xdotool type --delay 80 '马斯克 身价多少？' 2>/dev/null")
ffi.C.usleep(300000)
os.execute("xdotool key Tab 2>/dev/null")
ffi.C.usleep(200000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(5000000)

-- [2/5] 截图（import 到文件，然后用 xclip 写入剪贴板）
flush("[2/5] 截图...\n")
os.execute(string.format("import -window root -crop %dx%d+%d+%d /tmp/ai_search.png 2>/dev/null", cw, ch, cx, cy))
os.execute("xclip -selection clipboard -t image/png -i /tmp/ai_search.png 2>/dev/null")
flush(string.format("  OK: /tmp/ai_search.png\n"))

-- [3/5] 激活微信
flush("[3/5] 激活微信...\n")
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

os.execute("xdotool getactivewindow getwindowgeometry > /tmp/wx_geo.txt 2>/dev/null")
local f = io.open("/tmp/wx_geo.txt")
local geo = f:read("*a"); f:close()
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
if not wx then flush("❌ 获取微信窗口失败\n"); os.exit(1) end

-- [4/5] 搜索 "丰"
flush("[4/5] 搜索 丰...\n")
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + 180, wy + 50))
ffi.C.usleep(500000)
os.execute("xdotool type --delay 300 '丰' 2>/dev/null")
ffi.C.usleep(300000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1500000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1500000)

-- [5/5] 粘贴发送
flush("[5/5] 粘贴发送...\n")
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(500000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(2000000)

flush("✅\n")