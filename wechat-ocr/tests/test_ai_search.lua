#!/usr/bin/env luajit
-- Chrome AI 搜索 → 分段滚动 → OCR 识别
-- 用法: luajit tests/test_ai_search.lua

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local function flush(s) io.write(s); io.flush() end
flush("=== AI 搜索 → OCR ===\n\n")

-- [1/5] Chrome 搜索
flush("[1/5] Chrome AI 搜索...\n")
os.execute("xdotool search --name 'Google Chrome' windowactivate --sync 2>/dev/null")
ffi.C.usleep(500000)
local chrome_wid = io.popen("xdotool search --name 'Google Chrome' 2>/dev/null | tail -1"):read("*l")
if not chrome_wid then flush("❌ Chrome 未找到\n"); os.exit(1) end

os.execute("xdotool getactivewindow getwindowgeometry > /tmp/chrome_geo.txt 2>/dev/null")
local f = io.open("/tmp/chrome_geo.txt")
local geo = f:read("*a"); f:close()
local cx = tonumber(geo:match("Position: (%d+)"))
local cy = tonumber(geo:match(",(%d+)"))
local cw = tonumber(geo:match("Geometry: (%d+)"))
local ch = tonumber(geo:match("x(%d+)"))
flush(string.format("  Chrome: (%d,%d) %dx%d\n", cx, cy, cw, ch))

os.execute("xdotool key --window " .. chrome_wid .. " ctrl+t 2>/dev/null")
ffi.C.usleep(500000)
os.execute("xdotool type --delay 80 '2008年金融危机详细过程？' 2>/dev/null")
ffi.C.usleep(300000)
os.execute("xdotool key Tab 2>/dev/null")
ffi.C.usleep(200000)
os.execute("xdotool key Return 2>/dev/null")

-- [2/5] 等待 AI 回答
flush("[2/5] 等待 AI 回答（10s）...\n")
ffi.C.usleep(10000000)

-- [3/5] 分段滚动 + OCR
flush("[3/5] 分段滚动 + OCR...\n")
local home = os.getenv("HOME")
os.execute(string.format("xdotool windowactivate %s 2>/dev/null", chrome_wid))
ffi.C.usleep(300000)

-- OCR 初始化
ffi.cdef[[
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*,const char*,const char*);
    char*         ocr_capture_all(ocr_engine_t*);
    void          ocr_free_string(char*);
    void          ocr_destroy(ocr_engine_t*);
]]
local ocr_lib = ffi.load("libwechat_ocr_core.so")
local e = ocr_lib.ocr_create(
    "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_det_infer.onnx",
    "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_rec_infer.onnx",
    "/opt/my-agent/wechat-ocr/ppocr_keys_v1.txt")
if not e or e == ffi.NULL then flush("❌ OCR 加载失败\n"); os.exit(1) end

local cjson = require("cjson")
local all_text = {}
local prev_text = ""

for i = 1, 15 do
    -- 每屏截图保存
    local seg_path = string.format("%s/ai_result_%02d.png", home, i)
    os.execute(string.format("import -window %s '%s' 2>/dev/null", chrome_wid, seg_path))
    os.execute(string.format("convert '%s' +repage -crop 1500x%d+0+0 +repage '%s' 2>/dev/null", seg_path, ch, seg_path))

    local s = ocr_lib.ocr_capture_all(e)
    if s and s ~= ffi.NULL then
        local d = cjson.decode(ffi.string(s))
        ocr_lib.ocr_free_string(s)
        for _, b in ipairs(d.boxes or {}) do
            if b.x >= cx and b.x <= cx + 1500 then
                table.insert(all_text, b.text)
            end
        end
    end

    for _ = 1, 5 do os.execute("xdotool click 5 2>/dev/null"); ffi.C.usleep(50000) end
    ffi.C.usleep(500000)
end
ocr_lib.ocr_destroy(e)

-- 输出
flush(string.format("\n=== OCR 结果 (%d 段文字) ===\n\n", #all_text))
for _, t in ipairs(all_text) do
    flush(t .. " ")
end
flush("\n✅\n")