#!/usr/bin/env luajit
-- WeChat OCR - 发送文件测试
-- 用法: luajit tests/test_send_file.lua [文件路径]

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local ocr = require("wechat_ocr")
local dir = "/opt/my-agent/wechat-ocr"
local filepath = arg[1] or os.getenv("HOME") .. "/wechat_third_icons.png"
local filename = filepath:match("([^/]+)$")  -- 只要文件名

io.write("=== 发送文件 ===\n")
io.write("文件: " .. filepath .. "\n\n"); io.flush()

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 加载OCR
io.write("定位...\n"); io.flush()
ocr.init(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
         dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
         dir.."/ppocr_keys_v1.txt")
local data = ocr.capture_raw()
if not data then io.write("❌ OCR失败\n"); os.exit(1) end

local col3 = data.win.x
local input_y = data.win.y + data.win.h - 175

-- 直接算第3个图标位置
local icon_x = col3 + 130
local icon_y = input_y - 40
io.write(string.format("点文件图标: (%d,%d)\n", icon_x, icon_y)); io.flush()
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", icon_x, icon_y))
ffi.C.usleep(800000)

-- 粘贴文件名
io.write("粘贴文件名: " .. filename .. "\n"); io.flush()
local f = io.open("/tmp/wechat_send_path.txt", "w")
f:write(filename); f:close()
os.execute("xclip -selection clipboard < /tmp/wechat_send_path.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(500000)

-- 回车
io.write("选择+发送...\n"); io.flush()
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(2000000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)
io.write("✅\n"); io.flush()

ocr.destroy()
