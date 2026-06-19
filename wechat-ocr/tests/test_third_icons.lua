#!/usr/bin/env luajit
-- ============================================================
-- WeChat OCR - 第三列小图标检测（纯 Lua + ImageMagick）
-- ============================================================
-- 功能: OCR定位第三列 → 截图第三列区域 → ImageMagick检测图标
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

-- 3. OCR 获取第三列边界
io.write("[2/5] OCR分析三列结构...\n"); io.flush()
local det = dir .. "/models/ch_PP-OCRv4_det_infer.onnx"
local rec = dir .. "/models/ch_PP-OCRv4_rec_infer.onnx"
local dict = dir .. "/ppocr_keys_v1.txt"

local engine = lib.ocr_create(det, rec, dict)
if engine == nil or engine == ffi.NULL then io.write("❌ OCR加载失败\n"); os.exit(1) end

local c_str = lib.ocr_capture(engine)
if c_str == nil or c_str == ffi.NULL then
    io.write("❌ OCR捕获失败\n"); lib.ocr_destroy(engine); os.exit(1)
end

local json_str = ffi.string(c_str)
lib.ocr_free_string(c_str)
lib.ocr_destroy(engine)

local ok, data = pcall(cjson.decode, json_str)
if not ok then io.write("❌ JSON解析失败\n"); os.exit(1) end

local col3_abs = data.win.x  -- 第三列起始（屏幕绝对坐标）
local col3_w = data.win.w
local col3_x = col3_abs - wx  -- 第三列相对于窗口的 x
io.write(string.format("  第三列: 窗口内x=%d 宽度=%dpx (%.0f%%)\n\n", col3_x, col3_w, col3_w/ww*100)); io.flush()

-- 4. 截图 + 裁剪第三列
local ts = os.date("%Y%m%d_%H%M%S")
local home = os.getenv("HOME")
local raw = "/tmp/wx_third_raw.png"
local outfile = home .. "/wechat_third_icons_" .. ts .. ".png"

os.execute(string.format("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null",
    col3_w, wh, col3_abs, wy, raw))

-- 5. 多阈值检测图标
io.write("[3/5] 多阈值检测图标...\n"); io.flush()

local function parse_components(cmd)
    local blobs = {}
    local pipe = io.popen(cmd)
    if not pipe then return blobs end
    for line in pipe:lines() do
        if line:match("^%s*%d+:") and not line:match("^%s*0:") then
            local id, w, h, x, y, area = line:match(
                "(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
            if w and h and x and y and area then
                table.insert(blobs, {
                    x = tonumber(x), y = tonumber(y),
                    w = tonumber(w), h = tonumber(h),
                    area = tonumber(area)
                })
            end
        end
    end
    pipe:close()
    return blobs
end

local all_blobs = {}
for thr = 180, 5, -5 do
    local pct = thr / 255 * 100
    local cmd = string.format(
        "convert '%s' -colorspace gray -threshold %.1f%%%% -negate " ..
        "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1",
        raw, pct)
    for _, b in ipairs(parse_components(cmd)) do
        table.insert(all_blobs, b)
    end
end

-- 基础过滤 + 去重
local filtered = {}
local seen = {}
for _, b in ipairs(all_blobs) do
    local ratio = b.w / b.h
    if b.h >= 6 and b.w >= 6 and ratio >= 0.35 and ratio <= 2.2
       and b.area >= 36 and b.area <= 4000 then
        local key = math.floor(b.x/8) * 10000 + math.floor(b.y/8)
        if not seen[key] then
            seen[key] = true
            table.insert(filtered, b)
        end
    end
end
table.sort(filtered, function(a,b) return a.y < b.y end)

-- 文字行过滤
local is_text = {}
for i = 1, #filtered do is_text[i] = false end
for i = 1, #filtered do
    if is_text[i] then goto continue end
    local a, neighbors = filtered[i], {}
    for j = 1, #filtered do
        if i ~= j and not is_text[j] then
            local b = filtered[j]
            if math.abs((a.y+a.h/2)-(b.y+b.h/2)) <= 15
               and math.abs((a.x+a.w/2)-(b.x+b.w/2)) <= 45 then
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
for i, b in ipairs(filtered) do
    if not is_text[i] then table.insert(icons, b) end
end
io.write(string.format("  第三列图标: %d\n\n", #icons)); io.flush()

-- 6. 标注输出
io.write("[4/5] 标注输出...\n"); io.flush()

local annotate_cmds = {}
-- 第三列分界线（相对于第三列裁剪图的 x=0）
table.insert(annotate_cmds, string.format(
    '-fill none -stroke "rgb(255,0,0)" -strokewidth 2 -draw "line 0,0 0,%d"', wh))
-- 标题
table.insert(annotate_cmds, string.format(
    '-fill "rgb(0,255,0)" -pointsize 16 -annotate +10+10 "第三列 %d 个小图标"', #icons))

for i, b in ipairs(icons) do
    table.insert(annotate_cmds, string.format(
        '-fill none -stroke "rgb(0,255,0)" -strokewidth 1 -draw "rectangle %d,%d %d,%d"',
        b.x, b.y, b.x + b.w, b.y + b.h))
    if b.y >= 12 then
        table.insert(annotate_cmds, string.format(
            '-fill "rgb(0,255,0)" -pointsize 10 -annotate +%d+%d "%d"',
            b.x, b.y - 10, i))
    end
end

os.execute(string.format("convert '%s' %s '%s' 2>/dev/null", raw,
    table.concat(annotate_cmds, " "), outfile))

local fh = io.open(outfile, "r")
if fh then
    local sz = fh:seek("end"); fh:close()
    io.write(string.format("  标记图: %s (%d KB)\n", outfile, sz/1024))
end

-- 7. 隐藏微信
io.write("[5/5] 隐藏微信...\n"); io.flush()
os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
io.write("  微信已隐藏\n")
