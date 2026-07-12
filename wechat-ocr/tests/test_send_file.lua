#!/usr/bin/env luajit
-- WeChat OCR - 发送文件测试（聊天已打开状态，直接点工具栏发送文件）
-- 用法: luajit tests/test_send_file.lua [文件路径]

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;/opt/my-agent/wechat-ocr/lua/?.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[
    void usleep(unsigned int);
    int  joycaption_init(const char*, const char*, int);
    const char* joycaption_analyze(const char*, const char*);
    void joycaption_free();
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*, const char*, const char*);
    char*         ocr_capture(ocr_engine_t*);
    void          ocr_free_string(char*);
    void          ocr_destroy(ocr_engine_t*);
]]

local function flush(s) io.write(s); io.flush() end

local filepath = arg[1] or os.getenv("HOME") .. "/wechat_screen_record.mp4"

flush(string.format("=== 发送文件: %s ===\n\n", filepath))

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 获取窗口位置
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/wx_geo.txt 2>/dev/null")
local f = io.open("/tmp/wx_geo.txt")
local geo = f:read("*a"); f:close()
local _, _, wx = geo:find("Position: (%d+)")
local _, _, wy = geo:find(",(%d+)")
local _, _, ww = geo:find("Geometry: (%d+)")
local _, _, wh = geo:find("x(%d+)")
wx, wy, ww, wh = tonumber(wx), tonumber(wy), tonumber(ww), tonumber(wh)
if not wx then flush("❌ 获取窗口失败\n"); os.exit(1) end

-- OCR 获取第三列边界
local ocr_lib = ffi.load("libwechat_ocr_core.so")
local col3_x, col3_w = 0, ww
local e = ocr_lib.ocr_create(
    "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_det_infer.onnx",
    "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_rec_infer.onnx",
    "/opt/my-agent/wechat-ocr/ppocr_keys_v1.txt")
if e and e ~= ffi.NULL then
    local cjson = require("cjson")
    local s = ocr_lib.ocr_capture(e)
    if s and s ~= ffi.NULL then
        local d = cjson.decode(ffi.string(s))
        ocr_lib.ocr_free_string(s)
        col3_x = d.win.x - wx
        col3_w = d.win.w
    end
    ocr_lib.ocr_destroy(e)
end

local tool_y = math.max(wh - 430, 0)
local tool_h = 55

local toolbar_cache = require("toolbar_cache")
local icons = toolbar_cache.load()

-- [1/3] 定位发送文件图标
flush("[1/3] 定位发送文件图标...\n")
local folder_rel = nil

if icons then
    for _, icon in ipairs(icons) do
        if icon.name == "Folder" then
            folder_rel = icon
            flush(string.format("  cache: Folder rel=(%d,%d)\n", icon.rel_x, icon.rel_y))
            break
        end
    end
end

if not folder_rel then
    flush("  缓存未命中，VLM 识别...\n")
    local raw_strip = "/tmp/wx_send_toolbar.png"
    os.execute(string.format("import -window root -crop %dx%d+%d+%d +repage '%s' 2>/dev/null",
        col3_w, tool_h, wx + col3_x, wy + tool_y, raw_strip))

    local libjoy = ffi.load("libjoycaption")
    local ok = libjoy.joycaption_init(
        "/data/models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf",
        "/data/models/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf", 1)
    if ok ~= 0 then flush("❌ VLM 加载失败\n"); os.exit(1) end

    local result = ffi.string(libjoy.joycaption_analyze(raw_strip,
        [[List each icon from left to right in the WeChat formatting toolbar.
For each give number and English name.

Format: "1. Emoji"
]]))
    flush(string.format("  VLM: %s\n", result:gsub("\n", " | ")))

    local vlm_names = {}
    for line in result:gmatch("[^\n]+") do
        local name = line:match("^%d+%.%s*(%w+)")
        if name then table.insert(vlm_names, name) end
    end

    local all_boxes = {}
    for _, thr in ipairs({180, 140, 100, 60}) do
        local pct = thr / 255 * 100
        local cmd = string.format(
            "convert '%s' -colorspace gray -threshold %.1f%%%% -negate " ..
            "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1 " ..
            "| grep -v 'bgcolor\\|id:\\|0:.*srgb'", raw_strip, pct)
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

    local tmp = {}
    for _, b in ipairs(all_boxes) do
        local ratio = b.w / b.h
        if ratio >= 0.3 and ratio <= 4.0 and b.area >= 25 and b.area <= 6000 then
            b.cx = b.x + b.w / 2; b.cy = b.y + b.h / 2
            table.insert(tmp, b)
        end
    end
    table.sort(tmp, function(a,b) return b.area < a.area end)
    local merged = {}
    for _, b in ipairs(tmp) do
        local dup = false
        for _, m in ipairs(merged) do
            if (b.cx - m.cx)^2 + (b.cy - m.cy)^2 < 625 then dup = true; break end
        end
        if not dup then table.insert(merged, b) end
    end
    table.sort(merged, function(a,b) return a.x < b.x end)

    -- 构建 icons 列表并缓存（相对窗口 0,0）
    icons = {}
    for i, name in ipairs(vlm_names) do
        local b = merged[i]
        if b then
            table.insert(icons, {
                name  = name,
                rel_x = math.floor(b.cx + col3_x),
                rel_y = math.floor(b.cy + tool_y),
                w     = b.w,
                h     = b.h,
            })
            if name == "Folder" then folder_rel = icons[#icons] end
        end
    end
    toolbar_cache.save(icons)
    libjoy.joycaption_free()
end

-- 点击 Folder
if folder_rel then
    local cx = wx + folder_rel.rel_x
    local cy = wy + folder_rel.rel_y
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", cx, cy))
    ffi.C.usleep(800000)
    flush(string.format("  Folder → (%d,%d)\n", cx, cy))
else
    flush("⚠️ 未找到 Folder，回退位置\n")
    local cx = wx + col3_x + 130
    local cy = wy + wh - 175 - 40
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", cx, cy))
    ffi.C.usleep(800000)
end

-- [2/3] 在文件弹窗中输入路径
flush("[2/3] 输入文件名...\n")
ffi.C.usleep(1500000)
local safe_path = filepath:gsub("'", "'\\''")
os.execute("xdotool type --delay 80 '" .. safe_path .. "' 2>/dev/null")
ffi.C.usleep(500000)

-- [3/3] 回车选择 + 回车发送
flush("[3/3] 回车选择+发送...\n")
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(2000000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(2000000)
flush("✅ 文件已发送\n")
