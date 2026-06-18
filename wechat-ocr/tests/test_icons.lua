#!/usr/bin/env luajit
-- WeChat OCR - 第三列小图标检测测试
-- 功能: OCR识别 → 时间戳定位第三列 → 底部找小图标 → 标注
--
-- 用法:
--   export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib
--   export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
--   export LUA_CPATH="/usr/local/lualib/?.so;;"
--   luajit tests/test_icons.lua

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
local cjson = require("cjson")

ffi.cdef[[
    void usleep(unsigned int);
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*, const char*, const char*);
    char*         ocr_capture(ocr_engine_t*);
    void          ocr_free_string(char*);
    void          ocr_destroy(ocr_engine_t*);
    const char*   ocr_last_error(ocr_engine_t*);
]]

local lib = ffi.load("libwechat_ocr_core.so")
local project_dir = "/opt/my-agent/wechat-ocr"

local function run()
    io.write("=== WeChat 第三列小图标检测 ===\n\n")

    -- 1. 激活微信
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    ffi.C.usleep(500000)
    local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
    local _, _, wx = geo:find("Position: (%d+)")
    local _, _, wy = geo:find(",(%d+)")
    local _, _, ww = geo:find("Geometry: (%d+)")
    local _, _, wh = geo:find("x(%d+)")
    wx, wy, ww, wh = tonumber(wx), tonumber(wy), tonumber(ww), tonumber(wh)
    io.write(string.format("窗口: (%d,%d) %dx%d\n", wx, wy, ww, wh))

    -- 2. 加载OCR
    io.write("加载OCR...\n")
    local engine = lib.ocr_create(
        project_dir.."/models/ch_PP-OCRv4_det_infer.onnx",
        project_dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
        project_dir.."/ppocr_keys_v1.txt")
    if engine == nil or engine == ffi.NULL then io.write("❌ OCR失败\n"); return end

    -- 3. OCR识别获取第三列位置
    local s = lib.ocr_capture(engine)
    if s == nil or s == ffi.NULL then io.write("❌ 捕获失败\n"); return end
    local d = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)
    local col3 = d.win.x  -- 第三列起始屏幕坐标
    io.write(string.format("第三列: x=%d\n\n", col3))

    -- 4. 调用 Python 找图标
    io.write("找小图标...\n")
    local cmd = string.format(
        "/data/venv/bin/python3 tests/find_icons.py %d %d %d %d %d 2>/dev/null",
        col3, wx, wy, ww, wh)
    os.execute(cmd)
    io.write("标记图: ~/wechat_icons_test.png\n")

    lib.ocr_destroy(engine)
    io.write("完成\n")
end

local ok, err = pcall(run)
if not ok then io.write("❌ "..tostring(err).."\n"); os.exit(1) end
