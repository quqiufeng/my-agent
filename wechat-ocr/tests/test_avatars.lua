#!/usr/bin/env luajit
-- WeChat OCR - 第二列头像检测
-- 完全用OCR，不涉及颜色检测
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
io.write("=== 第二列头像(OCR) ===\n\n"); io.flush()

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx+40, wy+110))
ffi.C.usleep(1000000)

-- 截微信窗口
os.execute(string.format("import -window $(xdotool search --name 微信 | head -1) /tmp/avo.png 2>/dev/null"))

-- OCR全窗口
local e = lib.ocr_create(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
                          dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
                          dir.."/ppocr_keys_v1.txt")
local s = lib.ocr_capture_all(e)
local boxes = {}
if s and s ~= ffi.NULL then
    local d = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)
    boxes = d.boxes or {}
    local win = d.win
    io.write(string.format("OCR找到 %d 个文字框\n", #boxes))

    -- 第二列中方形文字框 → 头像上的文字
    local n = 0
    for _, b in ipairs(boxes) do
        if b.x < win.w * 0.40 then
            local ratio = b.w / b.h
            if ratio > 0.5 and ratio < 2.0 and b.h > 15 then
                n = n + 1
                io.write(string.format("  #%d: (%d,%d) %dx%d %s\n", n, win.x+b.x, win.y+b.y, b.w, b.h, b.text))
            end
        end
    end
    io.write(string.format("方形文字框: %d 个\n", n))
end
lib.ocr_destroy(e)
