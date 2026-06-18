#!/usr/bin/env luajit
-- WeChat OCR - 第三列小图标检测
-- 先OCR定位第三列 → 再扫描第三列找图标 → 标注

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
local cjson = require("cjson")

ffi.cdef[[
    void usleep(unsigned int);
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*,const char*,const char*);
    char* ocr_capture(ocr_engine_t*);
    void ocr_free_string(char*);
    void ocr_destroy(ocr_engine_t*);
]]

local lib = ffi.load("libwechat_ocr_core.so")
local dir = "/opt/my-agent/wechat-ocr"

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))

io.write(string.format("窗口: (%d,%d) %dx%d\n", wx, wy, ww, wh))

-- OCR获取第三列边界
local e = lib.ocr_create(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
                          dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
                          dir.."/ppocr_keys_v1.txt")
local s = lib.ocr_capture(e)
if s and s ~= ffi.NULL then
    local d = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)
    local col3 = d.win.x
    io.write(string.format("第三列: x=%d (%dpx)\n", col3, col3-wx))

    local cmd = string.format(
        "/data/venv/bin/python3 tests/find_third_icons.py %d %d %d %d %d 2>/dev/null",
        col3, wx, wy, ww, wh)
    os.execute(cmd)
end
lib.ocr_destroy(e)
