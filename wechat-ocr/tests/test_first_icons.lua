#!/usr/bin/env luajit
-- ============================================================
-- WeChat OCR - 第一列小图标检测（基于三列分割）
-- ============================================================
-- 功能: OCR三列分割 → 标注三列 → 检测第一列图标
--
-- 一键测试命令:
--   cd /opt/my-agent/wechat-ocr && \
--   export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib && \
--   export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;" && \
--   export LUA_CPATH="/usr/local/lualib/?.so;;" && \
--   luajit tests/test_first_icons.lua
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

io.write("=== 第一列小图标检测 ===\n\n"); io.flush()

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

-- 截图（先截，不管OCR是否成功都有图）
local ts = os.date("%Y%m%d_%H%M%S")
local home = os.getenv("HOME")
local outfile = home .. "/wechat_first_icons_" .. ts .. ".png"
os.execute(string.format("import -window root -crop %dx%d+%d+%d '/tmp/wx_first_raw.png' 2>/dev/null", ww, wh, wx, wy))

-- 3. OCR 获取三列边界
io.write("[2/5] OCR分析三列结构...\n"); io.flush()
local engine = lib.ocr_create(
    dir.."/models/ch_PP-OCRv4_det_infer.onnx",
    dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
    dir.."/ppocr_keys_v1.txt")

local col2_rel = 0
local ocr_ok = false
if engine and engine ~= ffi.NULL then
    local s = lib.ocr_capture(engine)
    if s and s ~= ffi.NULL then
        local d = cjson.decode(ffi.string(s))
        lib.ocr_free_string(s)
        col2_rel = d.win.x - wx
        ocr_ok = true
        io.write(string.format("  第三列边界: x=%d (%.0f%%)\n\n", col2_rel, col2_rel/ww*100)); io.flush()
    else
        io.write("  OCR跳过（" .. ffi.string(lib.ocr_last_error(engine)) .. "）\n\n"); io.flush()
    end
    lib.ocr_destroy(engine)
end

-- 4. 检测第一列图标（ImageMagick多阈值）
io.write("[3/5] 检测第一列图标...\n"); io.flush()

local COL1 = 75
local all_lines = {}
-- 方法: 找所有和背景色不同的区域
-- 第一列背景统一为 (237,237,237)，提取底色后做差值
-- 用 -fx 计算每个像素和背景的差异，然后阈值化
for _, sep in ipairs({3, 5, 8, 12}) do
    local diff = sep * 100 / 255  -- 转为百分比
    local cmd = string.format(
        "convert '/tmp/wx_first_raw.png' -crop %dx%d+0+0 -colorspace gray " ..
        "-fx 'abs(u - 237/255)' -threshold %.1f%%%% " ..
        "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1 " ..
        "| grep -v 'bgcolor\\|id:\\|0:.*gray'",
        COL1, wh, diff)
    local pipe = io.popen(cmd)
    if pipe then
        for line in pipe:lines() do
            local id, w, h, x, y, area = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
            if w and h and x and y and area then
                table.insert(all_lines, {x=tonumber(x), y=tonumber(y), w=tonumber(w), h=tonumber(h), area=tonumber(area)})
            end
        end
        pipe:close()
    end
end

-- 基础过滤 + 去重
local blobs = {}
local seen = {}
for _, b in ipairs(all_lines) do
    local ratio = b.w / b.h
    if b.h >= 5 and b.w >= 5 and ratio >= 0.3 and ratio <= 2.5 and b.area >= 25 and b.area <= 4000 then
        local key = math.floor(b.x/6) * 10000 + math.floor(b.y/6)
        if not seen[key] then
            seen[key] = true
            table.insert(blobs, b)
        end
    end
end
table.sort(blobs, function(a,b) return a.y < b.y end)

-- 文字行过滤
local is_text = {}
for i = 1, #blobs do is_text[i] = false end
for i, a in ipairs(blobs) do
    if is_text[i] then goto continue end
    local neighbors = {}
    for j, b in ipairs(blobs) do
        if i ~= j and not is_text[j] then
            local dy = math.abs((a.y + a.h/2) - (b.y + b.h/2))
            local dx = math.abs((a.x + a.w/2) - (b.x + b.w/2))
            if dy <= 15 and dx <= 25 then
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
for i, b in ipairs(blobs) do
    if not is_text[i] then table.insert(icons, b) end
end
io.write(string.format("  第一列图标: %d\n", #icons)); io.flush()

-- 5. 标注输出
io.write("[4/5] 标注输出...\n"); io.flush()

local cmds = {}
-- 第一列分割线 (75px)
table.insert(cmds, string.format(
    '-fill none -stroke "rgb(0,0,255)" -strokewidth 2 -draw "line %d,0 %d,%d"', COL1, COL1, wh))
-- 第三列分割线（如果OCR成功）
if ocr_ok then
    table.insert(cmds, string.format(
        '-fill none -stroke "rgb(255,0,0)" -strokewidth 2 -draw "line %d,0 %d,%d"', col2_rel, col2_rel, wh))
end
-- 标题
table.insert(cmds, string.format(
    '-fill "rgb(0,255,0)" -pointsize 16 -annotate +10+10 "第一列 %d 个小图标"', #icons))
if ocr_ok then
    table.insert(cmds, string.format(
        '-fill "rgb(255,0,0)" -pointsize 14 -annotate +%d+10 "第三列"' , col2_rel + 5))
end

-- 图标框
for i, b in ipairs(icons) do
    table.insert(cmds, string.format(
        '-fill none -stroke "rgb(0,255,0)" -strokewidth 1 -draw "rectangle %d,%d %d,%d"',
        b.x, b.y, b.x + b.w, b.y + b.h))
    if b.y >= 12 then
        table.insert(cmds, string.format(
            '-fill "rgb(0,255,0)" -pointsize 10 -annotate +%d+%d "%d"', b.x, b.y - 10, i))
    end
end

os.execute(string.format("convert '/tmp/wx_first_raw.png' %s '%s' 2>/dev/null",
    table.concat(cmds, " "), outfile))

local fh = io.open(outfile, "r")
if fh then
    local sz = fh:seek("end"); fh:close()
    io.write(string.format("  标记图: %s (%d KB)\n", outfile, sz/1024))
end

-- 6. 隐藏微信
io.write("[5/5] 隐藏微信...\n"); io.flush()
os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
io.write("  微信已隐藏\n")
