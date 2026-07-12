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

-- [3/5] 分段滚动 + OCR 屏幕（只取主内容区域）
flush("[3/5] 分段滚动 + OCR...\n")
local home = os.getenv("HOME")
os.execute(string.format("xdotool windowactivate %s 2>/dev/null", chrome_wid))
ffi.C.usleep(300000)
os.execute(string.format("xdotool mousemove --window %s %d %d click 1 2>/dev/null", chrome_wid, cw/2, ch/2))
ffi.C.usleep(300000)

-- 主内容区域边界（左 65%）
local content_x = math.floor(cw * 0.05)
local content_w = math.floor(cw * 0.65)

-- OCR 初始化
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
local all_text = {}
local prev_mean

for i = 1, 50 do
    -- OCR 当前屏幕
    local s = ocr_lib.ocr_capture_all(e)
    if s and s ~= ffi.NULL then
        local d = cjson.decode(ffi.string(s))
        ocr_lib.ocr_free_string(s)
        for _, b in ipairs(d.boxes or {}) do
            local bx = b.x - cx  -- 相对 Chrome 窗口的坐标
            -- 只取主内容区（左 65%，跳过右侧栏）
            if bx >= content_x and bx <= content_x + content_w then
                table.insert(all_text, b.text)
            end
        end
    end

    -- 检测是否到底：截图比较
    os.execute(string.format("import -window %s /tmp/_ai_chk.png 2>/dev/null", chrome_wid))
    local cur = io.popen("convert /tmp/_ai_chk.png -colorspace gray -scale 1x1! -format '%[fx:mean]' info: 2>/dev/null"):read("*a")
    if prev_mean and cur and math.abs(tonumber(cur) - tonumber(prev_mean)) < 0.001 then
        flush(string.format("  到底了（%d 屏）\n", i))
        break
    end
    prev_mean = cur

    -- 滚轮
    os.execute("xdotool click 5 2>/dev/null")
    ffi.C.usleep(300000)
end
ocr_lib.ocr_destroy(e)

-- 保存截图
os.execute(string.format("import -window %s '%s/ai_result.png' 2>/dev/null", chrome_wid, home))
flush(string.format("  截图保存: %s/ai_result.png\n", home))

-- 输出结果
flush(string.format("\n=== OCR 结果 (%d 段文字) ===\n\n", #all_text))
local seen = {}
for _, t in ipairs(all_text) do
    if not seen[t] then
        flush(t .. " ")
        seen[t] = true
    end
end
flush("\n✅\n")