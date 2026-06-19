#!/usr/bin/env luajit
-- ============================================================
-- WeChat OCR - 第三列小图标检测
-- ============================================================
-- 功能: OCR定位第三列边界 → 截图第三列区域 → 检测标注小图标
--
-- 一键测试命令:
--   cd /opt/my-agent/wechat-ocr && \
--   export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib && \
--   export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;" && \
--   export LUA_CPATH="/usr/local/lualib/?.so;;" && \
--   luajit tests/test_third_icons.lua
--
-- ============================================================
-- 整体流程
-- ============================================================
-- 步骤1: C++ OCR引擎 (libwechat_ocr_core.so) 分析三列结构
--   ocr_capture() 返回第三列起始边界 (data.win.x)
--   边界由以下算法动态计算:
--     a) 有时间戳 HH:MM → 右边缘聚类最大值 +20px
--     b) 无时间戳 → Canny垂直投影找竖线（10%~45%扫描）
--     c) 无竖线 → 聊天名称最右边缘 +50px
--
-- 步骤2: Python CV 检测第三列区域的小图标
--   只扫描第三列 ROI（col3_x ~ 窗口右边缘）
--   多阈值二值化（180→5步长-5），从深到浅全覆盖
--   基础过滤：最小6×6px，宽高比0.35~2.2，面积36~4000
--   文字行过滤：±15px Y内、间距<45px的邻居≥4个 → 判为文字
--
-- 步骤3: 标注输出
--   绿色框标注图标位置并编号
--   红色竖线标注第三列分界
--   输出 ~/wechat_third_icons_YYYYMMDD_HHMMSS.png
-- ============================================================

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
local dir = "/opt/my-agent/wechat-ocr"

io.write("=== 第三列小图标检测 ===\n\n"); io.flush()

-- 1. 激活微信
io.write("[1/4] 激活微信...\n"); io.flush()
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 2. 获取窗口几何
local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
if not wx then io.write("❌ 获取窗口失败\n"); os.exit(1) end
io.write(string.format("  窗口: (%d,%d) %dx%d\n\n", wx, wy, ww, wh)); io.flush()

-- 3. OCR 获取第三列边界
io.write("[2/4] OCR分析三列结构...\n"); io.flush()
local det = dir .. "/models/ch_PP-OCRv4_det_infer.onnx"
local rec = dir .. "/models/ch_PP-OCRv4_rec_infer.onnx"
local dict = dir .. "/ppocr_keys_v1.txt"

local engine = lib.ocr_create(det, rec, dict)
if engine == nil or engine == ffi.NULL then
    io.write("❌ OCR加载失败\n"); os.exit(1)
end

local c_str = lib.ocr_capture(engine)
if c_str == nil or c_str == ffi.NULL then
    io.write("❌ OCR捕获失败: " .. ffi.string(lib.ocr_last_error(engine)) .. "\n")
    lib.ocr_destroy(engine); os.exit(1)
end

local json_str = ffi.string(c_str)
lib.ocr_free_string(c_str)
lib.ocr_destroy(engine)

local ok, data = pcall(cjson.decode, json_str)
if not ok then
    io.write("❌ JSON解析失败\n"); os.exit(1)
end

local col3_x = data.win.x  -- 第三列起始边界（屏幕绝对坐标）
local col3_w = data.win.w  -- 第三列宽度
io.write(string.format("  第三列: x=%d 宽度=%dpx (%.0f%%)\n\n", col3_x, col3_w, col3_w/ww*100)); io.flush()

-- 4. Python 检测第三列图标
io.write("[3/4] 检测第三列图标...\n"); io.flush()
local ts = os.date("%Y%m%d_%H%M%S")
local outfile = os.getenv("HOME") .. "/wechat_third_icons_" .. ts .. ".png"
local cmd = string.format(
    "/data/venv/bin/python3 tests/find_third_icons.py %d %d %d %d %d '%s' 2>/dev/null",
    col3_x, wx, wy, ww, wh, outfile)
os.execute(cmd)

-- 5. 隐藏微信
io.write("[4/4] 隐藏微信...\n"); io.flush()
os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
io.write("  微信已隐藏\n")
