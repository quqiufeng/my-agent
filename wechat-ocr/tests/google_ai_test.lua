#!/usr/bin/env luajit
-- Chrome AI 搜索 → 分段截图 → 逐张微信发送
-- 用法: luajit tests/google_ai_test.lua

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local function flush(s) io.write(s); io.flush() end
flush("=== AI 搜索 → 分段截图 → 微信 ===\n\n")

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
os.execute("xdotool type --delay 80 '阿波罗登月计划的详细过程' 2>/dev/null")
ffi.C.usleep(300000)
os.execute("xdotool key Tab 2>/dev/null")
ffi.C.usleep(200000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(10000000)

-- [2/5] 先打开微信搜索 "丰"（首次聊天）
flush("[2/5] 打开微信聊天...\n")
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/wx_geo.txt 2>/dev/null")
local fgeo = io.open("/tmp/wx_geo.txt")
local wgeo = fgeo:read("*a"); fgeo:close()
local wx = tonumber(wgeo:match("Position: (%d+)"))
local wy = tonumber(wgeo:match(",(%d+)"))
if not wx then flush("❌ 微信窗口失败\n"); os.exit(1) end

os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + 180, wy + 50))
ffi.C.usleep(500000)
os.execute("xdotool type --delay 300 '丰' 2>/dev/null")
ffi.C.usleep(300000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1500000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1500000)

-- [3/5] 分段截图发送
flush("[3/5] 分段截图发送...\n")
local home = os.getenv("HOME")

-- OCR 初始化（用于内容去重）
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
local prev_text = ""

for i = 1, 15 do
    -- 截图左 1500px
    local seg_path = string.format("%s/ai_result_%02d.png", home, i)
    os.execute(string.format("import -window %s '%s' 2>/dev/null", chrome_wid, seg_path))
    os.execute(string.format("convert '%s' +repage -crop 1500x%d+0+0 +repage '%s' 2>/dev/null", seg_path, ch, seg_path))

    -- OCR 内容去重检测到底
    local s = ocr_lib.ocr_capture_all(e)
    if s and s ~= ffi.NULL then
        local d = cjson.decode(ffi.string(s))
        ocr_lib.ocr_free_string(s)
        local cur = ""
        for _, b in ipairs(d.boxes or {}) do
            if b.x >= cx and b.x <= cx + 1500 then cur = cur .. b.text end
        end
        if i > 1 and cur == prev_text then
            flush(string.format("  到底了（%d 张）\n", i - 1))
            break
        end
        prev_text = cur
    end

    -- 发送到微信
    os.execute(string.format("xclip -selection clipboard -t image/png -i '%s' 2>/dev/null", seg_path))
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    ffi.C.usleep(300000)
    os.execute("xdotool key ctrl+v 2>/dev/null")
    ffi.C.usleep(500000)
    os.execute("xdotool key Return 2>/dev/null")
    ffi.C.usleep(2000000)
    flush(string.format("  #%02d 已发送\n", i))

    -- 切回 Chrome 再滚动
    os.execute(string.format("xdotool windowactivate %s 2>/dev/null", chrome_wid))
    ffi.C.usleep(200000)
    for _ = 1, 5 do os.execute("xdotool click 5 2>/dev/null"); ffi.C.usleep(50000) end
    ffi.C.usleep(500000)
end
ocr_lib.ocr_destroy(e)
flush("✅\n")