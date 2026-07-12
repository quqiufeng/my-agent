#!/usr/bin/env luajit
-- 第三栏小工具图标 VLM 识别 → 标注图

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;/opt/my-agent/wechat-ocr/lua/?.lua;" .. (package.path or "")
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
    int  joycaption_init(const char*, const char*, int);
    const char* joycaption_analyze(const char*, const char*);
    void joycaption_free();
]]

local function printf(...) io.write(string.format(...)); io.flush() end

local MODEL = "/data/models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"
local MMPROJ = "/data/models/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf"
local LIBJOY = "/opt/my-agent/joycaption-wrapper/libjoycaption.so"

printf("=== 第三栏小工具图标 VLM 识别 + 标注 ===\n\n")

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 窗口几何
local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
if not wx then printf("❌ 获取窗口失败\n"); os.exit(1) end
printf("窗口: (%d,%d) %dx%d\n", wx, wy, ww, wh)

-- OCR 获取第三列边界
local function get_col3_bounds()
    local lib = ffi.load("libwechat_ocr_core.so")
    local e = lib.ocr_create(
        "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_det_infer.onnx",
        "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_rec_infer.onnx",
        "/opt/my-agent/wechat-ocr/ppocr_keys_v1.txt")
    if e and e ~= ffi.NULL then
        local s = lib.ocr_capture(e)
        if s and s ~= ffi.NULL then
            local d = cjson.decode(ffi.string(s))
            lib.ocr_free_string(s)
            lib.ocr_destroy(e)
            return d.win.x - wx, d.win.w
        end
        lib.ocr_destroy(e)
    end
    return 0, ww
end

local col3_x, col3_w = get_col3_bounds()
printf("第三列: x=%d w=%d\n", col3_x, col3_w)

-- 全窗口截图
local ts = os.date("%Y%m%d_%H%M%S")
local home = os.getenv("HOME")
local raw_full = "/tmp/wx_toolbar_full.png"
os.execute(string.format("import -window root -crop %dx%d+%d+%d +repage '%s' 2>/dev/null",
    ww, wh, wx, wy, raw_full))

-- 裁剪工具栏区域
local tool_y = math.max(wh - 430, 0)
local tool_h = 55
local raw_strip = "/tmp/wx_toolbar_strip.png"
os.execute(string.format("convert '%s' -crop %dx%d+%d+%d +repage '%s' 2>/dev/null",
    raw_full, col3_w, tool_h, col3_x, tool_y, raw_strip))

-- Connected components 检测图标
printf("检测工具栏图标...\n")
local all_boxes = {}
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
                table.insert(all_boxes, {x=tonumber(x), y=tonumber(y), w=tonumber(w), h=tonumber(h), area=tonumber(area)})
            end
        end
        pipe:close()
    end
end

-- 过滤
local tmp = {}
for _, b in ipairs(all_boxes) do
    local ratio = b.w / b.h
    if ratio >= 0.3 and ratio <= 4.0 and b.area >= 25 and b.area <= 6000 then
        b.cx = b.x + b.w / 2
        b.cy = b.y + b.h / 2
        table.insert(tmp, b)
    end
end
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
table.sort(merged, function(a,b) return a.x < b.x end)

printf("检测到 %d 个图标组件\n", #merged)

-- 加载 VLM
printf("加载 VLM...\n")
local libjoy = ffi.load(LIBJOY)
local ok = libjoy.joycaption_init(MODEL, MMPROJ, 1)
if ok ~= 0 then printf("❌ VLM 加载失败\n"); os.exit(1) end

local prompt = [[You are looking at the formatting toolbar of a WeChat chat window.
List each icon from left to right. For each one give:
- Number (1, 2, 3...)
- English name of what it represents (e.g., "Bold", "Italic", "Emoji", "Image", etc.)
- Brief visual description

Format: "1. Bold - B icon"
]]

local result = ffi.string(libjoy.joycaption_analyze(raw_strip, prompt))
printf("=== VLM 识别结果 ===\n%s\n", result)

libjoy.joycaption_free()

-- 解析 VLM 输出（提取名称）
local vlm_names = {}
for line in result:gmatch("[^\n]+") do
    local name = line:match("^%d+%.%s*(%w+)")
    if name then table.insert(vlm_names, name) end
end

printf("解析到 %d 个名称: %s\n", #vlm_names, table.concat(vlm_names, ", "))

-- 生成标注图
local cmds = {}
-- 第三列红色边框
table.insert(cmds, string.format(
    '-fill none -stroke "rgb(255,0,0)" -strokewidth 2 -draw "rectangle %d,%d %d,%d"',
    col3_x, tool_y, col3_x + col3_w, tool_y + tool_h))
-- 标题
table.insert(cmds, '-fill "rgb(0,255,0)" -pointsize 16 -annotate +10+10 "格式工具栏 VLM 识别"')

-- 标注每个图标
local n = math.min(#vlm_names, #merged)
for i = 1, n do
    local b = merged[i]
    local abs_x = col3_x + b.x
    local abs_y = tool_y + b.y
    table.insert(cmds, string.format(
        '-fill none -stroke "rgb(0,255,0)" -strokewidth 1 -draw "rectangle %d,%d %d,%d"',
        abs_x, abs_y, abs_x + b.w, abs_y + b.h))
    table.insert(cmds, string.format(
        '-fill "rgb(255,255,0)" -pointsize 11 -annotate +%d+%d "%s"',
        abs_x, abs_y - 2, vlm_names[i]))
end

local outfile = home .. "/wechat_toolbar_labels_" .. ts .. ".png"
local all_cmds = table.concat(cmds, " ")
os.execute(string.format("convert '%s' %s '%s' 2>/dev/null", raw_full, all_cmds, outfile))

local fh = io.open(outfile, "r")
if fh then
    local sz = fh:seek("end"); fh:close()
    printf("✅ 标记图: %s (%d KB)\n", outfile, sz/1024)
else
    printf("❌ 标记图生成失败\n")
end

-- 隐藏微信
os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
printf("微信已隐藏\n")
