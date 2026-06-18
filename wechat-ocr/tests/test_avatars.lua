#!/usr/bin/env luajit
-- WeChat OCR - 第二列头像检测标注
-- OCR定位文字 → 推算头像位置 → 出图标注
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

-- 获取窗口位置
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/av_win.txt 2>/dev/null")
local f = io.open("/tmp/av_win.txt")
local geo = f:read("*a"); f:close()
local _, _, ww = geo:find("Geometry: (%d+)")
local _, _, wh = geo:find("x(%d+)")
ww, wh = tonumber(ww), tonumber(wh)
io.write(string.format("窗口: %dx%d\n", ww, wh)); io.flush()

-- OCR检测
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

    -- 第二列文字按Y分组
    local items = {}
    for _, b in ipairs(boxes) do
        local cx = b.x + b.w / 2
        if cx < win.w * 0.35 and #b.text > 1 then
            table.insert(items, {cy=b.y+b.h/2, x=b.x, y=b.y, text=b.text, w=b.w})
        end
    end
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

    for _, g in ipairs(groups) do
        local first = g[1]
        local ax = win.x + first.x - 50
        local ay = win.y + first.y
        table.insert(avatars, {x=ax, y=ay, w=35, h=35, text=first.text})
    end
end
lib.ocr_destroy(e)

-- 出图标注（截微信窗口）
os.execute("import -window $(xdotool search --name 微信 | head -1) /tmp/av_full.png 2>/dev/null")

local out = {}
for _, a in ipairs(avatars) do table.insert(out, a) end
local f = io.open("/tmp/av_data.json","w")
f:write(cjson.encode({avatars=out})); f:close()

os.execute("/data/venv/bin/python3 tests/mark_avatars.py 2>/dev/null")
