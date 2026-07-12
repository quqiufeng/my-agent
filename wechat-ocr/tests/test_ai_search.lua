#!/usr/bin/env luajit
-- Chrome AI 搜索 → 截图 → OCR 识别
-- 用法: luajit tests/test_ai_search.lua

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local function flush(s) io.write(s); io.flush() end
flush("=== AI 搜索 → OCR ===\n\n")

-- [1/5] Chrome 搜索
flush("[1/5] Chrome AI 搜索...\n")
os.execute("xdotool search --name 'Google Chrome' windowactivate --sync 2>/dev/null")
ffi.C.usleep(500000)

-- 保存 Chrome 窗口 ID
local chrome_wid = io.popen("xdotool search --name 'Google Chrome' 2>/dev/null | tail -1"):read("*l")
if not chrome_wid then flush("❌ Chrome 未找到\n"); os.exit(1) end
flush(string.format("  Chrome WID: %s\n", chrome_wid))

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
os.execute("xdotool type --delay 80 '马斯克 身价多少？' 2>/dev/null")
ffi.C.usleep(300000)
os.execute("xdotool key Tab 2>/dev/null")
ffi.C.usleep(200000)
os.execute("xdotool key Return 2>/dev/null")

-- [2/5] 等待 AI 回答
flush("[2/5] 等待 AI 回答（10s）...\n")
ffi.C.usleep(10000000)

-- [3/5] 滚动到页面最下方
flush("[3/5] 滚动到页面底部...\n")
os.execute("xdotool key --window " .. chrome_wid .. " End 2>/dev/null")
ffi.C.usleep(1000000)

-- [4/5] 截图（用窗口 ID 确保截到 Chrome）
flush("[4/5] 截图...\n")
os.execute(string.format("xdotool windowactivate %s 2>/dev/null", chrome_wid))
ffi.C.usleep(500000)
os.execute(string.format("import -window %s /tmp/ai_result.png 2>/dev/null", chrome_wid))

-- [5/5] OCR 识别
flush("[5/5] OCR 识别...\n")
ffi.cdef[[
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*,const char*,const char*);
    char*         ocr_capture(ocr_engine_t*);
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
local s = ocr_lib.ocr_capture_all(e)
if s and s ~= ffi.NULL then
    local d = cjson.decode(ffi.string(s))
    ocr_lib.ocr_free_string(s)
    flush(string.format("\n=== OCR 结果 (%d 个文字框) ===\n\n", #(d.boxes or {})))
    for _, b in ipairs(d.boxes or {}) do
        flush(b.text .. " ")
    end
    flush("\n")
end
ocr_lib.ocr_destroy(e)
flush("\n✅\n")