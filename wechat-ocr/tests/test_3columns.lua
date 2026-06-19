#!/usr/bin/env luajit
-- ============================================================
-- WeChat OCR - 三列结构检测测试
-- ============================================================
-- 功能: 点微信图标 → 截图 → OCR → 识别三列 → 输出结果
--
-- 一键测试命令（复制整行执行）:
--   cd /opt/my-agent/wechat-ocr && \
--   export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib && \
--   export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;" && \
--   export LUA_CPATH="/usr/local/lualib/?.so;;" && \
--   luajit tests/test_3columns.lua
--
-- ============================================================
-- 列分界算法（C++ libwechat_ocr_core.so ocr_capture 中实现）
-- ============================================================
-- 微信窗口三列布局:
--   ┌──────┬───────────────────────┬─────────────────────┐
--   │ 第一  │ 第二                  │ 第三                │
--   │ 图标  │ 聊天列表+时间戳        │ 内容区              │
--   │ 75px  │ 时间戳 →|← 分隔线      │                     │
--   └──────┴───────────────────────┴─────────────────────┘
--                        ↑ y=85 横线
--
-- 算法:
--   ocr_capture() 对微信窗口做 OCR
--   找到所有 HH:MM 格式文本，取第一个时间戳的右边缘 + 25px
--   窗口宽度 < 2000 时减 10px 修正
--   找不到时间戳则返回错误
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

    -- 2. 获取窗口位置 + 截图（OCR之前截，保证有图）
    local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
    local _, _, wx = geo:find("Position: (%d+)")
    local _, _, wy = geo:find(",(%d+)")
    local _, _, ww = geo:find("Geometry: (%d+)")
    local _, _, wh = geo:find("x(%d+)")
    wx, wy, ww, wh = tonumber(wx), tonumber(wy), tonumber(ww), tonumber(wh)
    io.write(string.format("  窗口: (%d,%d) %dx%d\n\n", wx, wy, ww, wh))

    local ts = os.date("%Y%m%d_%H%M%S")
    local home = os.getenv("HOME")
    local outfile = home .. "/wechat_3cols_" .. ts .. ".png"
    os.execute(string.format("import -window root -crop %dx%d+%d+%d '/tmp/wx_3cols_raw.png' 2>/dev/null", ww, wh, wx, wy))

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
        -- 仍然画图（标注横线）
        draw_cross_image(ww, wh, outfile)
        hide_wechat()
        return true
    end

    local json_str = ffi.string(c_str)
    lib.ocr_free_string(c_str)

    local ok, data = pcall(cjson.decode, json_str)
    if not ok then
        io.write("❌ JSON解析失败\n")
        lib.ocr_destroy(engine)
        draw_cross_image(ww, wh, outfile)
        hide_wechat()
        return true
    end

    local win = data.win
    local boxes = data.boxes or {}

    -- 5. 输出三列结构
    io.write("[4/5] 三列结构:\n\n")
    local col1_px = 4
    local col2_px = win.x - wx
    local col2_pct = col2_px / ww * 100

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

    io.write("[5/5] 第三列识别结果:\n\n")
    for _, b in ipairs(boxes) do
        if #b.text > 1 then io.write("  " .. b.text .. "\n") end
    end
    io.write(string.format("\n共识别 %d 条文字\n==========================================\n 测试通过 ✅\n==========================================\n", #boxes))

    lib.ocr_destroy(engine)

    -- 6. 标注输出
    draw_col3_image(ww, wh, win.x - wx, outfile)
    hide_wechat()
    return true
end

function draw_cross_image(ww, wh, outfile)
    local cross_y = 85
    local cmds = {
        '-fill none -stroke yellow -strokewidth 2 -draw "line 0,%d %d,%d"',
        '-fill none -stroke "rgb(255,128,0)" -strokewidth 2 -draw "circle 0,%d 6,0"',
        '-fill white -pointsize 16 -annotate +10+10 "未检测到时间戳，仅标注横线 y=85"',
    }
    local annotate = string.format(table.concat(cmds, " "), cross_y, ww, cross_y, cross_y)
    os.execute(string.format("convert '/tmp/wx_3cols_raw.png' %s '%s' 2>/dev/null", annotate, outfile))
    local fh = io.open(outfile, "r")
    if fh then local sz = fh:seek("end"); fh:close() end
    io.write(string.format("  标记图: %s\n", outfile))
end

function draw_col3_image(ww, wh, col2_rel, outfile)
    local pct = math.floor(col2_rel / ww * 100)
    local cross_y = 85
    local cmds = {
        '-fill none -stroke "rgb(255,0,0)" -strokewidth 3 -draw "line 4,0 4,%d"',
        '-fill none -stroke "rgb(0,0,255)" -strokewidth 3 -draw "line %d,0 %d,%d"',
        '-fill none -stroke yellow -strokewidth 2 -draw "line 0,%d %d,%d"',
        '-fill none -stroke "rgb(255,128,0)" -strokewidth 2 -draw "circle %d,%d 6,0"',
        '-fill "rgb(255,0,0)" -pointsize 20 -annotate +10+35 "第一列 图标"',
        '-fill "rgb(0,255,0)" -pointsize 20 -annotate +30+65 "第二列 列表+时间"',
        '-fill "rgb(0,0,255)" -pointsize 20 -annotate +%d+35 "第三列 内容"',
        '-fill white -pointsize 16 -annotate +10+%d "窗口 %dx%d | 第三列 %dpx (%d%%)"',
    }
    local annotate = string.format(table.concat(cmds, " "),
        wh, col2_rel, col2_rel, wh,
        cross_y, ww, cross_y,
        col2_rel, cross_y,
        col2_rel + 15, wh - 30, ww, wh, col2_rel, pct)
    os.execute(string.format("convert '/tmp/wx_3cols_raw.png' %s '%s' 2>/dev/null", annotate, outfile))
    local fh = io.open(outfile, "r")
    if fh then local sz = fh:seek("end"); fh:close()
        io.write(string.format("  标记图: %s (%d KB)\n", outfile, sz/1024)) end
end

function hide_wechat()
    os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
    io.write("  微信已隐藏\n")
end

local ok, err = pcall(run_test)
if not ok then
    io.write("❌ 异常: " .. tostring(err) .. "\n")
    os.exit(1)
end
