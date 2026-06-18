#!/usr/bin/env luajit
-- WeChat OCR - 第二列红色未读数检测
-- 用OCR全窗口识别，找第二列中的数字（红色未读标记）
-- 用法: luajit tests/test_unread_detect.lua

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
io.write("=== 第二列红色未读数检测 ===\n\n"); io.flush()

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

local e = lib.ocr_create(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
                          dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
                          dir.."/ppocr_keys_v1.txt")
if not e or e == ffi.NULL then io.write("❌ OCR失败\n"); os.exit(1) end

local s = lib.ocr_capture_all(e)
if not s or s == ffi.NULL then io.write("❌ 捕获失败\n"); os.exit(1) end

local d = cjson.decode(ffi.string(s))
lib.ocr_free_string(s)

local win = d.win
local boxes = d.boxes or {}
-- 第三列约从40%开始，第二列在 4%~40% 之间
local col3_x = win.x + math.floor(win.w * 0.40)

io.write(string.format("全窗口 %d 个文字框\n", #boxes))
io.write(string.format("第三列约从 x=%d\n\n", col3_x)); io.flush()

-- 在第二列中找数字
local count = 0
for _, b in ipairs(boxes) do
    local cx = b.x + b.w / 2
    if cx > 10 and cx < col3_x and b.text:match("^%d+$") then
        count = count + 1
        io.write(string.format("  🔴 #%d: \"%s\"  (%d,%d) %dx%d\n", count, b.text, b.x, b.y, b.w, b.h))
    end
end

if count == 0 then
    io.write("  未检测到红色数字（可能没有未读消息）\n")
else
    io.write(string.format("\n共 %d 个未读\n", count))
end
io.write("✅\n"); io.flush()
lib.ocr_destroy(e)
