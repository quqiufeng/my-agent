#!/usr/bin/env luajit
-- WeChat OCR - 搜索联系人测试
-- 流程: 找到第二列的搜索框 → 点击 → 输入"小王" → 回车
-- 用法: luajit tests/test_search.lua [搜索词]

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local ocr = require("wechat_ocr")
local cjson = require("cjson")
local dir = "/opt/my-agent/wechat-ocr"
local keyword = arg[1] or "小王"

io.write("=== 搜索: " .. keyword .. " ===\n"); io.flush()

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 加载OCR
io.write("定位搜索框...\n"); io.flush()
ocr.init(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
         dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
         dir.."/ppocr_keys_v1.txt")

-- 获取原始数据（全窗口，不做第三列过滤）
local data = ocr.capture_raw()
if not data then
    -- fallback: 估算位置
    local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
    local col3_x = tonumber(geo:match("Geometry: (%d+)")) or 2560
    col3_x = math.floor(col3_x * 0.40)  -- 约40%
    local sx = 50
    local sy = 60
    io.write(string.format("估算搜索框: (%d,%d)\n", sx, sy)); io.flush()
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", sx, sy))
    ffi.C.usleep(300000)
    -- 输入关键词
    io.write("输入: " .. keyword .. "\n"); io.flush()
    local f = io.open("/tmp/wechat_search.txt", "w")
    f:write(keyword); f:close()
    os.execute("xclip -selection clipboard < /tmp/wechat_search.txt 2>/dev/null")
    ffi.C.usleep(100000)
    os.execute("xdotool key ctrl+v 2>/dev/null")
    ffi.C.usleep(300000)
    os.execute("xdotool key Return 2>/dev/null")
    io.write("✅\n"); io.flush()
    ocr.destroy()
    os.exit(0)
end

-- 在全部box中找到"搜索"文字的位置
local boxes = data.boxes or {}
local sx, sy = 0, 0
for _, b in ipairs(boxes) do
    if b.text == "搜索" or b.text == "🔍" then
        sx = b.x + b.w / 2
        sy = b.y + b.h / 2
        break
    end
end

if sx == 0 then
    -- 没找到"搜索"文字，用估算
    local win_w = data.win.w
    local win_x = data.win.x
    sx = win_x + math.floor(win_w * 0.25)  -- 第二列中间偏左
    sy = data.win.y + 45
    io.write("⚠️ 未找到搜索文字，用估算位置\n"); io.flush()
end

io.write(string.format("点击搜索框: (%d,%d)\n", sx, sy)); io.flush()
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", math.floor(sx), math.floor(sy)))
ffi.C.usleep(500000)

-- 输入关键词
io.write("输入: " .. keyword .. "\n"); io.flush()
local f = io.open("/tmp/wechat_search.txt", "w")
f:write(keyword); f:close()
os.execute("xclip -selection clipboard < /tmp/wechat_search.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(300000)

-- 回车搜索
io.write("搜索...\n"); io.flush()
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)
io.write("✅\n"); io.flush()

ocr.destroy()
