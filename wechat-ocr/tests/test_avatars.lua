#!/usr/bin/env luajit
-- WeChat OCR - 第二列头像检测
-- 方法1: OCR方形文字框（群聊头像有首字）
-- 方法2: OCR聊天名称文本（个人聊天用名称位置推算）
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

os.execute("xdotool getactivewindow getwindowgeometry > /tmp/av9.txt 2>/dev/null")
local f = io.open("/tmp/av9.txt")
local geo = f:read("*a"); f:close()
local _, _, ww = geo:find("Geometry: (%d+)")
local _, _, wh = geo:find("x(%d+)")
ww, wh = tonumber(ww), tonumber(wh)
io.write(string.format("窗口: %dx%d\n", ww, wh)); io.flush()

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

    -- 收集第二列所有文字
    local items = {}
    for _, b in ipairs(boxes) do
        if b.x < win.w * 0.40 and #b.text > 0 then
            local ratio = b.w / b.h
            table.insert(items, {bx=b.x, by=b.y, bw=b.w, bh=b.h, text=b.text, ratio=ratio})
        end
    end

    -- 按Y分组
    table.sort(items, function(a,b) return a.by < b.by end)
    local groups, cur_y, cur_g = {}, 0, {}
    for _, t in ipairs(items) do
        if #cur_g == 0 or math.abs(t.by - cur_y) < 30 then
            table.insert(cur_g, t); cur_y = t.by
        else
            table.insert(groups, cur_g); cur_g = {t}; cur_y = t.by
        end
    end
    if #cur_g > 0 then table.insert(groups, cur_g) end

    -- 每组判断是头像有字（方形）还是需要推算
    for _, g in ipairs(groups) do
        local has_square = false
        local first = g[1]
        for _, t in ipairs(g) do
            if t.ratio > 0.7 and t.ratio < 1.5 and t.bh > 18 then
                -- 方形框：是群聊头像上的字，直接用它
                local ax = t.bx - 25
                local ay = t.by - 25
                table.insert(avatars, {x=ax, y=ay, w=75, h=75, text="["..t.text.."]"})
                has_square = true
                break
            end
        end
        if not has_square then
            -- 没有方形框：用聊天名称推算（名称在头像右边）
            local name = first
            local ax = name.bx - 50
            local ay = name.by - 15
            table.insert(avatars, {x=ax, y=ay, w=75, h=75, text=name.text:sub(1,6)})
        end
    end
end
lib.ocr_destroy(e)

io.write(string.format("头像: %d 个\n", #avatars))

-- 出图
os.execute("import -window $(xdotool search --name 微信 | head -1) /tmp/av_win3.png 2>/dev/null")
local f3 = io.open("/tmp/av_data5.json","w")
f3:write("{\"avatars\":[")
for i, a in ipairs(avatars) do
    if i > 1 then f3:write(",") end
    f3:write(string.format('{"x":%d,"y":%d,"w":%d,"h":%d,"text":"%s"}', a.x, a.y, a.w, a.h, a.text))
end
f3:write("]}"); f3:close()

os.execute("/data/venv/bin/python3 tests/mark_avatars.py 2>/dev/null")
