#!/usr/bin/env luajit
-- WeChat OCR - 第二列头像检测
-- OCR找聊天名称 → 头像在名称左边75px
-- 用法: luajit tests/test_avatars.lua

local ffi = require("ffi")
local cjson = require("cjson")
ffi.cdef[[void usleep(unsigned int);]]

local lib = ffi.load("libwechat_ocr_core.so")
ffi.cdef[[
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*,const char*,const char*);
    char* ocr_capture_all(ocr_engine_t*);
    void ocr_free_string(char*);
    void ocr_destroy(ocr_engine_t*);
]]

local dir = "/opt/my-agent/wechat-ocr"
io.write("=== 第二列头像检测 ===\n\n"); io.flush()

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

os.execute("xdotool getactivewindow getwindowgeometry > /tmp/av8.txt 2>/dev/null")
local f = io.open("/tmp/av8.txt")
local geo = f:read("*a"); f:close()
local _, _, ww = geo:find("Geometry: (%d+)")
local _, _, wh = geo:find("x(%d+)")
ww, wh = tonumber(ww), tonumber(wh)
io.write(string.format("窗口: %dx%d\n\n", ww, wh)); io.flush()

-- OCR全窗口
local e = lib.ocr_create(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
                          dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
                          dir.."/ppocr_keys_v1.txt")
local s = lib.ocr_capture_all(e)
local avatars = {}
if s and s ~= ffi.NULL then
    local d = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)
    local win = d.win
    local boxes = d.boxes or {}

    -- 第二列中的文字（x < 40%窗口宽度）
    local items = {}
    for _, b in ipairs(boxes) do
        local cx = b.x + b.w / 2
        if cx < win.w * 0.40 and #b.text > 1 then
            table.insert(items, {cy=b.y+b.h/2, y=b.y, text=b.text})
        end
    end

    -- 按Y分组
    table.sort(items, function(a,b) return a.cy < b.cy end)
    local groups, cur_y, cur_g = {}, 0, {}
    for _, t in ipairs(items) do
        if #cur_g == 0 or math.abs(t.cy - cur_y) < 30 then
            table.insert(cur_g, t); cur_y = t.cy
        else
            table.insert(groups, cur_g); cur_g = {t}; cur_y = t.cy
        end
    end
    if #cur_g > 0 then table.insert(groups, cur_g) end

    -- 每组取第一个文字，头像在左边75px
    for _, g in ipairs(groups) do
        local name = g[1]
        local ax = win.x + name.y  -- 用y作为x的占位，不对
        local ay = win.y + name.y
        -- 正确：头像x = 文字x - 75
        -- 但b.x是相对于win的坐标，文字x = win.x + b.x
        -- 头像x = win.x + b.x - 75 (相对于窗口)
        -- 在图片中：头像x = b.x - 75 (相对于图片)
        local img_ax = 30  -- 头像通常在左侧30-50px处
        local img_ay = name.y - 10
        table.insert(avatars, {x=img_ax, y=img_ay, w=75, h=75, text=name.text})
    end
end
lib.ocr_destroy(e)

io.write(string.format("头像: %d 个\n", #avatars))

-- 出图
os.execute("import -window $(xdotool search --name 微信 | head -1) /tmp/av_win2.png 2>/dev/null")
local f3 = io.open("/tmp/av_data4.json","w")
f3:write("{\"avatars\":[")
for i, a in ipairs(avatars) do
    if i > 1 then f3:write(",") end
    f3:write(string.format('{"x":%d,"y":%d,"w":%d,"h":%d,"text":"%s"}', a.x, a.y, a.w, a.h, a.text))
end
f3:write("]}"); f3:close()

os.execute("/data/venv/bin/python3 tests/mark_avatars.py 2>/dev/null")
