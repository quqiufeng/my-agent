#!/usr/bin/env luajit
-- WeChat OCR - 第二列头像检测
-- 用OCR文字位置推算头像位置（头像在聊天名称左边）
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

local e = lib.ocr_create(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
                          dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
                          dir.."/ppocr_keys_v1.txt")
if not e or e == ffi.NULL then io.write("❌ OCR失败\n"); os.exit(1) end

local s = lib.ocr_capture_all(e)
if s and s ~= ffi.NULL then
    local d = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)
    local win = d.win
    local boxes = d.boxes or {}

    -- 第二列的文字
    local items = {}
    for _, b in ipairs(boxes) do
        local cx = b.x + b.w / 2
        if cx < win.w * 0.4 and #b.text > 1 then
            table.insert(items, {cy=b.y+b.h/2, x=b.x, y=b.y, text=b.text})
        end
    end

    -- 按Y分组
    table.sort(items, function(a,b) return a.cy < b.cy end)
    local groups = {}
    local cur_y, cur_g = 0, {}
    for _, t in ipairs(items) do
        if #cur_g == 0 or math.abs(t.cy - cur_y) < 30 then
            table.insert(cur_g, t); cur_y = t.cy
        else
            table.insert(groups, cur_g); cur_g = {t}; cur_y = t.cy
        end
    end
    if #cur_g > 0 then table.insert(groups, cur_g) end

    io.write(string.format("头像 %d 个:\n", #groups))
    for i, g in ipairs(groups) do
        local first = g[1]
        local av_x = win.x + first.x - 45
        local av_y = win.y + first.y
        io.write(string.format("  #%d: (%d,%d) - %s\n", i, av_x, av_y, first.text))
    end
end
lib.ocr_destroy(e)
