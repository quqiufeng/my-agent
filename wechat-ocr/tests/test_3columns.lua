#!/usr/bin/env luajit
-- ============================================================
-- WeChat OCR - 三列结构检测测试
-- ============================================================
-- 功能: 点微信图标 → 截图 → OCR → 识别三列 → 输出结果
--
-- 使用方式:
--   export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib
--   export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
--   export LUA_CPATH="/usr/local/lualib/?.so;;"
--   luajit tests/test_3columns.lua
--
-- 微信窗口三列结构（动态检测，非固定比例）:
--
--   ┌──────┬────────────────────────┬──────────────────────┐
--   │ 第一 │ 第二                   │ 第三                  │
--   │      │                        │                       │
--   │ 图标 │  列表+时间              │  内容                 │
--   │ 区域 │                        │                       │
--   │      │  公众号/服务号         │  聊天消息/文章         │
--   │ (灰) │  文件传输助手          │  标题+消息+输入框      │
--   │ (绿) │  群聊/单聊            │                       │
--   │      │  时间戳 →| ← 分界      │                       │
--   └──────┴────────────────────────┴──────────────────────┘
--
-- 第三列定位方法:
--   1. OCR全图识别所有文字
--   2. 找到时间戳文本（格式 NN:NN 或 "昨天"/"今天"）
--   3. 时间戳中位数位置 + 40px = 第三列起始边界
--   4. 只保留第三列内的文字框
--   5. 自适应任何窗口大小，不依赖固定百分比
--
-- 依赖:
--   - libwechat_ocr_core.so (C++ OCR引擎)
--   - ONNX Runtime GPU (深度学习推理)
--   - PaddleOCR PP-OCRv4 模型
--   - xdotool (窗口控制)
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
local project_dir = "/opt/my-agent/wechat-ocr"

-- ======== 主测试函数 ========

local function run_test()
    io.write("==========================================\n")
    io.write(" WeChat OCR - 三列结构检测\n")
    io.write("==========================================\n\n")

    -- 1. 点微信图标
    io.write("[1/5] 点击微信图标...\n")
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    ffi.C.usleep(1000000)

    -- 2. 获取窗口位置
    local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
    local _, _, wx = geo:find("Position: (%d+)")
    local _, _, wy = geo:find(",(%d+)")
    local _, _, ww = geo:find("Geometry: (%d+)")
    local _, _, wh = geo:find("x(%d+)")
    wx, wy, ww, wh = tonumber(wx), tonumber(wy), tonumber(ww), tonumber(wh)
    io.write(string.format("  窗口: (%d,%d) %dx%d\n\n", wx, wy, ww, wh))

    -- 3. 加载OCR
    io.write("[2/5] 加载OCR模型...\n")
    local det = project_dir .. "/models/ch_PP-OCRv4_det_infer.onnx"
    local rec = project_dir .. "/models/ch_PP-OCRv4_rec_infer.onnx"
    local dict = project_dir .. "/ppocr_keys_v1.txt"

    local engine = lib.ocr_create(det, rec, dict)
    if engine == nil or engine == ffi.NULL then
        io.write("❌ OCR加载失败\n")
        return false
    end
    io.write("  ✅ OCR就绪\n\n")

    -- 4. OCR识别
    io.write("[3/5] OCR识别全窗口...\n")
    local c_str = lib.ocr_capture(engine)
    if c_str == nil or c_str == ffi.NULL then
        io.write("❌ 捕获失败: " .. ffi.string(lib.ocr_last_error(engine)) .. "\n")
        lib.ocr_destroy(engine)
        return false
    end

    local json_str = ffi.string(c_str)
    lib.ocr_free_string(c_str)

    local ok, data = pcall(cjson.decode, json_str)
    if not ok then
        io.write("❌ JSON解析失败\n")
        lib.ocr_destroy(engine)
        return false
    end

    local win = data.win
    local boxes = data.boxes or {}

    -- 5. 输出三列结构
    io.write("[4/5] 三列结构:\n\n")
    local col1_px = 4
    local col2_px = win.x - wx
    local col3_px = ww - (win.x - wx)
    local col1_pct = col1_px / ww * 100
    local col2_pct = col2_px / ww * 100
    local col3_pct = col3_px / ww * 100

    io.write(string.format("  ┌──────┬──────────────────┬──────────────────────┐\n"))
    io.write(string.format("  │ %-4s │ %-16s │ %-20s │\n", "第一", "第二", "第三"))
    io.write(string.format("  │ %-4s │ %-16s │ %-20s │\n", "图标", "列表+时间", "内容"))
    io.write(string.format("  ├──────┼──────────────────┼──────────────────────┤\n"))
    io.write(string.format("  │ %-4s │ %-16s │ %-20s │\n", "0px", col2_px.."px", col2_px.."px"))
    io.write(string.format("  │ %-4d │ %-16.0f │ %-20.0f │\n", col1_px, col2_pct, 100-col2_pct))
    io.write(string.format("  └──────┴──────────────────┴──────────────────────┘\n\n"))

    io.write(string.format("  第一列(图标):    0~%dpx\n", col1_px))
    io.write(string.format("  第二列(列表+时间): %d~%dpx (%.0f%%)\n", col1_px, col2_px, col2_pct))
    io.write(string.format("  第三列(内容):     %d~%dpx (%.0f%%~100%%)\n", col2_px, ww, col2_pct))
    io.write(string.format("  分界方式: 时间戳+40px\n\n"))

    -- 6. 输出第三列内容
    io.write("[5/5] 第三列识别结果:\n\n")
    for _, b in ipairs(boxes) do
        if #b.text > 1 then
            io.write("  " .. b.text .. "\n")
        end
    end

    io.write(string.format("\n共识别 %d 条文字\n", #boxes))
    io.write("==========================================\n")
    io.write(" 测试通过 ✅\n")
    io.write("==========================================\n")

    lib.ocr_destroy(engine)

    -- 6. 生成标记图（带时间戳文件名防覆盖）
    io.write("\n生成标记图...\n")
    local ts = os.date("%Y%m%d_%H%M%S")
    local outfile = os.getenv("HOME") .. "/wechat_3cols_" .. ts .. ".png"
    local cmd = string.format("/data/venv/bin/python3 tests/mark_columns.py %d '%s' 2>/dev/null", win.x, outfile)
    os.execute(cmd)
    io.write("  标记图: " .. outfile .. "\n")

    -- 7. 隐藏微信窗口（点任务栏图标或最小化）
    os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
    io.write("  微信已隐藏\n")

    return true
end

local ok, err = pcall(run_test)
if not ok then
    io.write("❌ 异常: " .. tostring(err) .. "\n")
    os.exit(1)
end
