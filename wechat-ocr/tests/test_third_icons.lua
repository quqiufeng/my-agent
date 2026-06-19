#!/usr/bin/env luajit
-- ============================================================
-- WeChat OCR - 第三列小图标检测（基于三列分割）
-- ============================================================
-- 功能: OCR定位第三列 → 背景差值+Canny检测图标 → 标注输出
--
-- 一键测试命令:
--   cd /opt/my-agent/wechat-ocr && \
--   export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib && \
--   export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;" && \
--   export LUA_CPATH="/usr/local/lualib/?.so;;" && \
--   luajit tests/test_third_icons.lua
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
io.write("[1/5] 激活微信...\n"); io.flush()
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

-- 3. OCR 获取第三列边界 + 截图
io.write("[2/5] OCR分析三列结构...\n"); io.flush()
local engine = lib.ocr_create(
    dir.."/models/ch_PP-OCRv4_det_infer.onnx",
    dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
    dir.."/ppocr_keys_v1.txt")

local col3_abs, col3_w = 0, ww
local ocr_ok = false
if engine and engine ~= ffi.NULL then
    local s = lib.ocr_capture(engine)
    if s and s ~= ffi.NULL then
        local d = cjson.decode(ffi.string(s))
        lib.ocr_free_string(s)
        col3_abs = d.win.x
        col3_w = d.win.w
        ocr_ok = true
    end
    lib.ocr_destroy(engine)
end

local col3_x = ocr_ok and (col3_abs - wx) or 0
if ocr_ok then
    io.write(string.format("  第三列: x=%d 宽度=%dpx (%.0f%%)\n\n", col3_x, col3_w, col3_w/ww*100))
else
    io.write("  OCR跳过，使用全窗口\n\n")
end
io.flush()

-- 截图（只截第三列底部工具区，全窗口用于标注）
local ts = os.date("%Y%m%d_%H%M%S")
local home = os.getenv("HOME")
local raw_full = "/tmp/wx_third_full.png"
local raw_tool = "/tmp/wx_third_tool.png"
local outfile = home .. "/wechat_third_icons_" .. ts .. ".png"
os.execute(string.format("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null", ww, wh, wx, wy, raw_full))

-- 只截工具栏区域（底部200px）
local tool_h = math.min(200, wh)
local tool_y = wy + wh - tool_h
os.execute(string.format("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null",
    ww, tool_h, wx, tool_y, raw_tool))

-- 4. 检测第三列工具栏图标
io.write("[3/5] 检测第三列图标...\n"); io.flush()

local all_lines = {}

-- 只在工具栏区域检测
for thr = 220, 80, -15 do
    local pct = thr / 255 * 100
    local cmd = string.format(
        "convert '%s' +repage -crop %dx%d+%d+0 -colorspace gray -threshold %.1f%%%% -negate " ..
        "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1 " ..
        "| grep -v 'bgcolor\\|id:\\|0:.*srgb'",
        raw_tool, col3_w, tool_h, col3_x, pct)
    local pipe = io.popen(cmd)
    if pipe then
        for line in pipe:lines() do
            local id, w, h, x, y, area = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
            if w and h and x and y and area then
                table.insert(all_lines, {x=col3_x+tonumber(x), y=tonumber(y) + wh - tool_h,
                                         w=tonumber(w), h=tonumber(h), area=tonumber(area)})
            end
        end
        pipe:close()
    end
end

-- 基础过滤
local tmp = {}
for _, b in ipairs(all_lines) do
    local ratio = b.w / b.h
    if b.h >= 5 and b.w >= 5 and ratio >= 0.25 and ratio <= 3.0 and b.area >= 25 and b.area <= 4000 then
        b.cx = b.x + b.w / 2
        b.cy = b.y + b.h / 2
        table.insert(tmp, b)
    end
end

-- 按面积排序，中心距离合并（22px半径）
table.sort(tmp, function(a,b) return b.area < a.area end)
local merged = {}
for _, b in ipairs(tmp) do
    local dup = false
    for _, m in ipairs(merged) do
        local dx = b.cx - m.cx
        local dy = b.cy - m.cy
        if dx*dx + dy*dy < 500 then dup = true; break end
    end
    if not dup then table.insert(merged, b) end
end
table.sort(merged, function(a,b) return a.y < b.y end)

-- 文字行过滤（第三列有文字）
local is_text = {}
for i = 1, #merged do is_text[i] = false end
for i = 1, #merged do
    if is_text[i] then goto continue end
    local a, neighbors = merged[i], {}
    for j = 1, #merged do
        if i ~= j and not is_text[j] then
            local b = merged[j]
            if math.abs(a.cy - b.cy) <= 15 and math.abs(a.cx - b.cx) <= 25 then
                table.insert(neighbors, j)
            end
        end
    end
    if #neighbors >= 4 then
        is_text[i] = true
        for _, j in ipairs(neighbors) do is_text[j] = true end
    end
    ::continue::
end

local icons = {}
for i, b in ipairs(merged) do
    if not is_text[i] then table.insert(icons, b) end
end
io.write(string.format("  第三列图标: %d\n\n", #icons)); io.flush()

-- 5. 标注输出
io.write("[4/5] 标注输出...\n"); io.flush()

local cmds = {}
-- 第三列红色边框
if ocr_ok then
    table.insert(cmds, string.format(
        '-fill none -stroke "rgb(255,0,0)" -strokewidth 2 -draw "rectangle %d,0 %d,%d"',
        col3_x, col3_x + col3_w, wh))
end
-- 标题
table.insert(cmds, string.format(
    '-fill "rgb(0,255,0)" -pointsize 16 -annotate +10+10 "第三列 %d 个小图标"', #icons))

for i, b in ipairs(icons) do
    table.insert(cmds, string.format(
        '-fill none -stroke "rgb(0,255,0)" -strokewidth 1 -draw "rectangle %d,%d %d,%d"',
        b.x, b.y, b.x + b.w, b.y + b.h))
    if b.y >= 12 then
        table.insert(cmds, string.format(
            '-fill "rgb(0,255,0)" -pointsize 10 -annotate +%d+%d "%d"', b.x, b.y - 10, i))
    end
end

os.execute(string.format("convert '%s' %s '%s' 2>/dev/null", raw, table.concat(cmds, " "), outfile))

local fh = io.open(outfile, "r")
if fh then
    local sz = fh:seek("end"); fh:close()
    io.write(string.format("  标记图: %s (%d KB)\n", outfile, sz/1024))
end

-- 6. 隐藏微信
io.write("[5/5] 隐藏微信...\n"); io.flush()
os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
io.write("  微信已隐藏\n")
