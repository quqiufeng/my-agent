#!/usr/bin/env luajit
-- WeChat OCR - 第二列头像检测
-- 用C库检测第二列聊天列表中的头像
-- 用法: luajit tests/test_avatars.lua

local ffi = require("ffi")
local cjson = require("cjson")
ffi.cdef[[void usleep(unsigned int);]]

local lib = ffi.load("libwechat_ocr_core.so")
ffi.cdef[[
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*,const char*,const char*);
    char* ocr_detect_avatars(ocr_engine_t*);
    void ocr_free_string(char*);
    void ocr_destroy(ocr_engine_t*);
]]

local dir = "/opt/my-agent/wechat-ocr"
io.write("=== 第二列头像检测 ===\n\n"); io.flush()

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

local e = lib.ocr_create(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
                          dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
                          dir.."/ppocr_keys_v1.txt")
if not e or e == ffi.NULL then io.write("❌ OCR失败\n"); os.exit(1) end

local s = lib.ocr_detect_avatars(e)
if s and s ~= ffi.NULL then
    local d = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)
    local avs = d.avatars or {}
    io.write(string.format("头像: %d 个\n", #avs))
    for i, a in ipairs(avs) do
        io.write(string.format("  #%d: (%d,%d) %dx%d\n", i, a.x, a.y, a.w, a.h))
    end
else
    io.write("❌ 检测失败\n")
end

io.write("✅\n"); io.flush()
lib.ocr_destroy(e)
