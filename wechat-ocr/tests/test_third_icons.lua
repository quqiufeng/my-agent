#!/usr/bin/env luajit
-- ============================================================
-- WeChat OCR - 第三列小图标检测（基于三列分割 + OCR文本过滤）
-- ============================================================
-- 功能: OCR定位第三列 → 全高度扫描 → OCR文本框过滤 → 标注输出
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

-- 3. OCR 获取第三列边界 + 文本框
io.write("[2/5] OCR分析三列结构...\n"); io.flush()
local engine = lib.ocr_create(
    dir.."/models/ch_PP-OCRv4_det_infer.onnx",
    dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
    dir.."/ppocr_keys_v1.txt")

local col3_abs, col3_w = 0, ww
local text_boxes = {}
local ocr_ok = false
if engine and engine ~= ffi.NULL then
    local s = lib.ocr_capture(engine)
    if s and s ~= ffi.NULL then
        local d = cjson.decode(ffi.string(s))
        lib.ocr_free_string(s)
        col3_abs = d.win.x
        col3_w = d.win.w
        text_boxes = d.boxes or {}
        ocr_ok = true
    end
    lib.ocr_destroy(engine)
end

local col3_x = ocr_ok and (col3_abs - wx) or 0
if ocr_ok then
    io.write(string.format("  第三列: x=%d 宽度=%dpx (%.0f%%), OCR文字框%d个\n\n", col3_x, col3_w, col3_w/ww*100, #text_boxes))
else
    io.write("  OCR跳过，使用全窗口\n\n")
end
io.flush()

-- 截图（全窗口用于标注 + 第三列全高度用于检测）
local ts = os.date("%Y%m%d_%H%M%S")
local home = os.getenv("HOME")
local raw_full = "/tmp/wx_third_full.png"
local outfile = home .. "/wechat_third_icons_" .. ts .. ".png"
os.execute(string.format("import -window root -crop %dx%d+%d+%d +repage '%s' 2>/dev/null", ww, wh, wx, wy, raw_full))

-- 过滤：只保留第三列内的文字框（转换为窗口相对坐标）
local function box_overlap(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2)
    return ax1 < bx2 and ax2 > bx1 and ay1 < by2 and ay2 > by1
end

local col3_texts = {}
for _, tb in ipairs(text_boxes) do
    local tx, ty, tw, th = tb.x or 0, tb.y or 0, tb.w or 0, tb.h or 0
    if tx + tw > col3_x and tx < col3_x + col3_w then
        table.insert(col3_texts, {x=tx, y=ty, w=tw, h=th})
    end
end
io.write(string.format("  第三列内文字框: %d个\n\n", #col3_texts)); io.flush()

-- 4. 分区检测图标：顶部图标(0-80px) + 底部格式工具栏(430px~485px)
io.write("[3/5] 检测第三列图标（分区扫描）...\n"); io.flush()

local all_lines = {}
local raw_col3 = "/tmp/wx_col3_full.png"
os.execute(string.format("import -window root -crop %dx%d+%d+%d +repage '%s' 2>/dev/null",
    col3_w, wh, wx + col3_x, wy, raw_col3))

local toolbar_y = math.max(wh - 430, 0)
local zones = {
    { name="顶部图标", y1=0, y2=80 },
    { name="格式工具栏", y1=toolbar_y, y2=toolbar_y + 55 },
}

local raw_strips = {}
for _, zone in ipairs(zones) do
    local zh = zone.y2 - zone.y1
    local strip_name = "/tmp/wx_strip_" .. zone.y1 .. ".png"
    raw_strips[zone.name] = strip_name
    os.execute(string.format("convert '%s' -crop %dx%d+0+%d +repage '%s' 2>/dev/null",
        raw_col3, col3_w, zh, zone.y1, strip_name))
    local fh = io.open(strip_name, "r")
    if fh then
        local sz = fh:seek("end"); fh:close()
        io.write(string.format("  分区 %s: %dx%d (%d KB)\n", zone.name, col3_w, zh, sz/1024))
    end
end
io.flush()

for _, zone in ipairs(zones) do
    local raw_strip = raw_strips[zone.name]

    for _, thr in ipairs({180, 140, 100, 60}) do
        local pct = thr / 255 * 100
        local cmd = string.format(
            "convert '%s' -colorspace gray -threshold %.1f%%%% -negate " ..
            "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1 " ..
            "| grep -v 'bgcolor\\|id:\\|0:.*srgb'",
            raw_strip, pct)
        local pipe = io.popen(cmd)
        if pipe then
            for line in pipe:lines() do
                local id, w, h, x, y, area = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
                if w and h and x and y and area then
                    table.insert(all_lines, {x=col3_x+tonumber(x), y=zone.y1+tonumber(y),
                                             w=tonumber(w), h=tonumber(h), area=tonumber(area)})
                end
            end
            pipe:close()
        end
    end
end

-- 基础过滤
local tmp = {}
for _, b in ipairs(all_lines) do
    local ratio = b.w / b.h
    -- 图标一般是近正方形，放宽到 0.4~2.5；最小面积 100（~10x10），最大 6000
    if ratio >= 0.3 and ratio <= 4.0 and b.area >= 25 and b.area <= 8000 then
        b.cx = b.x + b.w / 2
        b.cy = b.y + b.h / 2
        table.insert(tmp, b)
    end
end

-- 按面积排序，中心距离合并（25px半径）
table.sort(tmp, function(a,b) return b.area < a.area end)
local merged = {}
for _, b in ipairs(tmp) do
    local dup = false
    for _, m in ipairs(merged) do
        local dx = b.cx - m.cx
        local dy = b.cy - m.cy
        if dx*dx + dy*dy < 625 then dup = true; break end
    end
    if not dup then table.insert(merged, b) end
end
table.sort(merged, function(a,b) return a.y < b.y end)

-- OCR文本框过滤
local icons = {}
for _, b in ipairs(merged) do
    local is_text = false
    local bx1, by1, bx2, by2 = b.x, b.y, b.x + b.w, b.y + b.h
    for _, tb in ipairs(col3_texts) do
        local tx1, ty1, tx2, ty2 = tb.x, tb.y, tb.x + tb.w, tb.y + tb.h
        if box_overlap(bx1, by1, bx2, by2, tx1, ty1, tx2, ty2) then
            is_text = true
            break
        end
    end
    if not is_text then
        table.insert(icons, b)
    end
end

io.write(string.format("  第三列非文字组件: %d\n\n", #icons)); io.flush()

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
    '-fill "rgb(0,255,0)" -pointsize 16 -annotate +10+10 "第三列 %d 个非文字组件"', #icons))

for i, b in ipairs(icons) do
    table.insert(cmds, string.format(
        '-fill none -stroke "rgb(0,255,0)" -strokewidth 1 -draw "rectangle %d,%d %d,%d"',
        b.x, b.y, b.x + b.w, b.y + b.h))
    if b.y >= 12 then
        table.insert(cmds, string.format(
            '-fill "rgb(0,255,0)" -pointsize 10 -annotate +%d+%d "%d"', b.x, b.y - 10, i))
    end
end

os.execute(string.format("convert '%s' %s '%s' 2>/dev/null", raw_full, table.concat(cmds, " "), outfile))

local fh = io.open(outfile, "r")
if fh then
    local sz = fh:seek("end"); fh:close()
    io.write(string.format("  标记图: %s (%d KB)\n", outfile, sz/1024))
end

-- 6. 隐藏微信
io.write("[5/5] 隐藏微信...\n"); io.flush()
os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
io.write("  微信已隐藏\n")
