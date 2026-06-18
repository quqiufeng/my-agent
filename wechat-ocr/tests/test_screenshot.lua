#!/usr/bin/env luajit
-- WeChat OCR - 截图发送测试
-- 流程: 点2次截图图标 → 双击微信窗口 → 截图填入 → 发送
-- 用法: luajit tests/test_screenshot.lua

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local ocr = require("wechat_ocr")
local dir = "/opt/my-agent/wechat-ocr"

io.write("=== 截图发送 ===\n"); io.flush()

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 获取窗口位置
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/win_geo.txt 2>/dev/null")
local f = io.open("/tmp/win_geo.txt")
local geo = f:read("*a"); f:close()
local _, _, wx = geo:find("Position: (%d+)")
local _, _, wy = geo:find(",(%d+)")
local _, _, ww = geo:find("Geometry: (%d+)")
local _, _, wh = geo:find("x(%d+)")
wx, wy, ww, wh = tonumber(wx), tonumber(wy), tonumber(ww), tonumber(wh)
if not ww then io.write("❌ 获取窗口失败\n"); os.exit(1) end

-- 定位第三列
io.write("定位...\n"); io.flush()
ocr.init(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
         dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
         dir.."/ppocr_keys_v1.txt")
local data = ocr.capture_raw()
if not data then io.write("❌ OCR失败\n"); os.exit(1) end

local col3 = data.win.x
local input_y = data.win.y + data.win.h - 175

-- 第4个图标（截图）
local icon_x = col3 + 130 + 38
local icon_y = input_y - 40

-- 点一次截图图标进入截图模式
io.write(string.format("截图模式: (%d,%d)\n", icon_x, icon_y)); io.flush()
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", icon_x, icon_y))
ffi.C.usleep(500000)

-- 从 (0,0) 拖到 (2560,1440) 选全屏
io.write("框选全屏\n"); io.flush()
os.execute("xdotool mousemove 0 0 mousedown 1 mousemove 2560 1440 mouseup 1 2>/dev/null")
ffi.C.usleep(500000)

-- 双击确认
io.write("双击确认\n"); io.flush()
os.execute("xdotool click --repeat 2 1 2>/dev/null")
ffi.C.usleep(1000000)

-- 回车发送
io.write("发送...\n"); io.flush()
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)
io.write("✅\n"); io.flush()

ocr.destroy()
