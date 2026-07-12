#!/usr/bin/env luajit
-- 一次性图标校准脚本
-- VLM 扫描侧边栏 + 工具栏所有图标，保存相对窗口(0,0)的坐标到 ~/.wechat_icons.json
-- 之后所有操作只需 getwindowgeometry + 查表

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;/opt/my-agent/wechat-ocr/lua/?.lua;" .. (package.path or "")
package.cpath = "/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;" .. (package.cpath or "")

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

-- 激活微信并获取窗口
local function get_window()
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    ffi.C.usleep(500000)
    os.execute("xdotool getactivewindow getwindowgeometry > /tmp/wx_geo.txt 2>/dev/null")
    local f = io.open("/tmp/wx_geo.txt")
    local geo = f:read("*a"); f:close()
    local wx = tonumber(geo:match("Position: (%d+)"))
    local wy = tonumber(geo:match(",(%d+)"))
    local ww = tonumber(geo:match("Geometry: (%d+)"))
    local wh = tonumber(geo:match("x(%d+)"))
    if not wx then return nil end
    return {x=wx, y=wy, w=ww, h=wh}
end

-- 获取第三列边界（OCR）
local function get_col3(win)
    local ocr_lib = ffi.load("/opt/my-agent/wechat-ocr/lib/libwechat_ocr_core.so")
    local e = ocr_lib.ocr_create(
        "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_det_infer.onnx",
        "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_rec_infer.onnx",
        "/opt/my-agent/wechat-ocr/ppocr_keys_v1.txt")
    if not e or e == ffi.NULL then return nil end
    local cjson = require("cjson")
    local s = ocr_lib.ocr_capture(e)
    local col3_x, col3_w
    if s and s ~= ffi.NULL then
        local d = cjson.decode(ffi.string(s))
        col3_x = d.win.x - win.x
        col3_w = d.win.w
        ocr_lib.ocr_free_string(s)
    end
    ocr_lib.ocr_destroy(e)
    if not col3_x then return nil end
    return {x=col3_x, w=col3_w}
end

-- Connected Components 提取
local function detect_boxes(img_path, crop_w, crop_h)
    local all = {}
    for _, thr in ipairs({5, 10, 20, 30, 180, 140, 100, 60}) do
        local is_canny = thr <= 30
        local cmd
        if is_canny then
            cmd = string.format(
                "convert '%s' -colorspace gray -canny 0x1+%d%%%%+%d%%%% -negate " ..
                "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1 " ..
                "| grep -v 'bgcolor\\|id:\\|0:.*gray'",
                img_path, thr, thr * 2)
        else
            local pct = thr / 255 * 100
            cmd = string.format(
                "convert '%s' -colorspace gray -threshold %.1f%%%% -negate " ..
                "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1 " ..
                "| grep -v 'bgcolor\\|id:\\|0:.*srgb'", img_path, pct)
        end
        local pipe = io.popen(cmd)
        if pipe then
            for line in pipe:lines() do
                local id, w, h, x, y, area = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
                if w and h and x and y and area then
                    table.insert(all, {x=tonumber(x), y=tonumber(y), w=tonumber(w), h=tonumber(h), area=tonumber(area)})
                end
            end
            pipe:close()
        end
    end

    local tmp = {}
    for _, b in ipairs(all) do
        local ratio = b.w / b.h
        if b.h >= 6 and b.w >= 6 and ratio >= 0.3 and ratio <= 3.5 and b.area >= 15 and b.area <= 5000 then
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
    return merged
end

-- VLM 初始化
local function vlm_init()
    local paths = {
        "libjoycaption",
        "/opt/my-agent/joycaption-wrapper/libjoycaption.so",
        os.getenv("HOME") .. "/my-agent/joycaption-wrapper/libjoycaption.so",
    }
    local lib_path
    local lib
    for _, p in ipairs(paths) do
        local ok, l = pcall(ffi.load, p)
        if ok then lib = l; lib_path = p; break end
    end
    if not lib then return nil, "libjoycaption not found" end
    flush(string.format("  VLM 库: %s\n", lib_path))
    local ret = lib.joycaption_init(
        "/data/models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf",
        "/data/models/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf", 1)
    flush(string.format("  joycaption_init: %d\n", ret))
    if ret ~= 0 then return nil, "VLM init failed: " .. ret end
    return lib
end

-- ==== 校准开始 ====

flush("=== WeChat 图标校准 ===\n\n")
os.execute("rm -f ~/.wechat_icons.json")

-- 获取窗口
local win = get_window()
if not win then flush("❌ 获取窗口失败\n"); os.exit(1) end
flush(string.format("窗口: (%d,%d) %dx%d\n\n", win.x, win.y, win.w, win.h))

-- 截全窗
os.execute(string.format("import -window root -crop %dx%d+%d+%d '/tmp/calib_full.png' 2>/dev/null", win.w, win.h, win.x, win.y))

-- ==== 1. 侧边栏 ====
flush("[1/3] 检测侧边栏宽度...\n")
local COL1 = 75
local bg_pipe = io.popen("convert '/tmp/calib_full.png' +repage -crop 8x8+0+0 -colorspace gray -format '%[fx:mean*255]' info: 2>/dev/null")
local bg_val = 237
if bg_pipe then
    local s = bg_pipe:read("*a"); bg_pipe:close()
    bg_val = tonumber(s:match("[%d.]+")) or bg_val
end
local proj_cmd = string.format(
    "convert '/tmp/calib_full.png' +repage -crop 120x%d+0+0 -colorspace gray " ..
    "-fx 'abs(u - %d/255) > 0.04' -scale 1x%d! -scale 120x%d! " ..
    "txt:- 2>/dev/null | awk -F'[,:]' '/#FFFFFF/{print $1}' | sort -rn | head -1",
    win.h, bg_val, win.h, win.h)
local spipe = io.popen(proj_cmd, "r")
if spipe then
    local last_col = spipe:read("*a"):match("(%d+)")
    spipe:close()
    if last_col then
        local detected = tonumber(last_col) + 5
        if detected >= 30 and detected <= 110 then COL1 = detected end
    end
end
flush(string.format("  侧边栏宽: %dpx\n\n", COL1))

flush("[2/3] VLM 识别侧边栏图标...\n")
local lib = vlm_init()
if not lib then flush("❌ VLM 加载失败\n"); os.exit(1) end
flush("  VLM 已加载\n")

-- 裁剪侧边栏
os.execute(string.format("convert '/tmp/calib_full.png' +repage -crop %dx%d+0+0 '/tmp/calib_col1.png' 2>/dev/null", COL1, win.h))

-- VLM 识别（精简输出，避免描述浪费 token）
local prompt = [[List each icon in the WeChat left sidebar from top to bottom. List all visible icons.
Output only number and English name, no description.
Format: "1. Chats"]]
local result = lib.joycaption_analyze("/tmp/calib_col1.png", prompt)
if result == ffi.NULL then flush("❌ VLM 返回空\n"); os.exit(1) end
local vlm_text = ffi.string(result)
flush("  VLM: " .. vlm_text:gsub("\n", " | ") .. "\n\n")

-- 解析 VLM 名称
local vlm_names = {}
for line in vlm_text:gmatch("[^\n]+") do
    local name = line:match("^%d+%.%s*(%w+)")
    if name then table.insert(vlm_names, name) end
end

-- CC 检测主区域
local col1_boxes = detect_boxes("/tmp/calib_col1.png", COL1, win.h)

-- 对底部额外用更灵敏的阈值检测（从 y=400 到窗口底部）
local bottom_crop = "/tmp/calib_col1_bottom.png"
os.execute(string.format("convert '/tmp/calib_col1.png' +repage -crop %dx%d+0+%d '/tmp/calib_col1_bottom.png' 2>/dev/null",
    COL1, win.h - 400, 400))
local bottom_boxes = {}
for _, thr in ipairs({255, 240, 220, 200, 180, 160}) do
    local pct = thr / 255 * 100
    local cmd = string.format(
        "convert '%s' -colorspace gray -threshold %.1f%%%% -negate " ..
        "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1 " ..
        "| grep -v 'bgcolor\\|id:\\|0:.*srgb'", bottom_crop, pct)
    local pipe = io.popen(cmd)
    if pipe then
        for line in pipe:lines() do
            local id, w, h, x, y, area = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
            if w and h and x and y and area then
                table.insert(bottom_boxes, {x=tonumber(x), y=tonumber(y)+math.floor(win.h*0.6), w=tonumber(w), h=tonumber(h), area=tonumber(area)})
            end
        end
        pipe:close()
    end
end
-- 合并底部检测结果
for _, b in ipairs(bottom_boxes) do
    b.cx = b.x + b.w / 2
    b.cy = b.y + b.h / 2
    local ratio = b.w / b.h
    if b.h >= 6 and b.w >= 6 and ratio >= 0.3 and ratio <= 4.0 and b.area >= 10 and b.area <= 8000 then
        local dup = false
        for _, m in ipairs(col1_boxes) do
            local dx = b.cx - m.cx
            local dy = b.cy - m.cy
            if dx*dx + dy*dy < 625 then dup = true; break end
        end
        if not dup then table.insert(col1_boxes, b) end
    end
end

table.sort(col1_boxes, function(a,b) return a.y < b.y end)
flush(string.format("  CC 检测到 %d 个组件\n", #col1_boxes))
for i, b in ipairs(col1_boxes) do
    flush(string.format("    b%d: (%3d,%3d) %dx%d area=%d\n", i, math.floor(b.cx), math.floor(b.cy), b.w, b.h, b.area))
end

-- 按 Y 位置匹配 icon_actions 固定顺序
local icon_actions = require("icon_actions")
local sidebar_entries = {}
for _, v in pairs(icon_actions.defaults) do
    if v.area == "col1" then
        table.insert(sidebar_entries, v)
    end
end
table.sort(sidebar_entries, function(a,b) return a.order < b.order end)
local sidebar_order = {}
local seen_order = {}
for _, v in ipairs(sidebar_entries) do
    if not seen_order[v.order] then
        seen_order[v.order] = true
        sidebar_order[v.order] = v.name_en
    end
end

local sidebar_icons = {}
local icon_idx = 0
local prev_y = -100
for i, b in ipairs(col1_boxes) do
    -- 跳过 y 太接近底部或超出窗口的
    if b.cy > win.h - 30 then break end
    -- 跳过太小的噪点
    if b.area < 15 then break end
    -- 跳过间距太大的（非图标区域）
    if icon_idx > 0 and b.cy - prev_y > 200 then
        flush(string.format("  gap %dpx → 停止\n", b.cy - prev_y))
        break
    end

    icon_idx = icon_idx + 1
    prev_y = b.cy
    local expected_name = sidebar_order[icon_idx]
    local name, name_cn
    if expected_name then
        local entry = icon_actions.defaults[expected_name]
        name = entry and entry.name_en or expected_name
        name_cn = (entry and entry.name_cn) or name
    else
        -- 超出已知映射，用 VLM 或占位名
        name = vlm_names[icon_idx] or ("Icon" .. icon_idx)
        name_cn = name
    end
    table.insert(sidebar_icons, {
        name    = name,
        name_cn = name_cn,
        rel_x   = math.floor(b.cx),
        rel_y   = math.floor(b.cy),
        w       = b.w,
        h       = b.h,
    })
    flush(string.format("  %d. %-12s → (%3d, %3d)\n", icon_idx, name, math.floor(b.cx), math.floor(b.cy)))
end
flush("\n")

-- ==== 2. 工具栏 ====
flush("[3/3] VLM 识别工具栏图标...\n")

-- OCR 获取第三列
local col3 = get_col3(win)
if not col3 then
    flush("  OCR 失败，使用估算值\n")
    col3 = {x = 520, w = win.w - 520}
end
flush(string.format("  第三列 x=%d w=%d\n", col3.x, col3.w))

-- 校验 col3 合理性
if not col3 or col3.x < COL1 + 10 or col3.x > win.w * 0.8 or col3.w < 100 then
    flush("  OCR 结果不合理，使用估算值\n")
    col3 = {x = 520, w = win.w - 520}
end
local tool_y = math.max(win.h - 460, 0)
local tool_h = 90

-- 裁剪整个输入栏
os.execute(string.format("convert '/tmp/calib_full.png' +repage -crop %dx%d+%d+%d '/tmp/calib_toolbar.png' 2>/dev/null",
    col3.w, tool_h, col3.x, tool_y))

-- 先 VLM 识别整条输入栏
local toolbar_prompt = [[You are looking at the bottom input bar of WeChat chat window.
List each icon you see from left to right.
Expected icons: Emoji, Cube (or Gift/Collect), Folder (or File), Scissors (or Screenshot), Chat (or Chat History), Phone (or Call).
For each give number and English name.

Format: "1. Emoji"
]]
local t_result = lib.joycaption_analyze("/tmp/calib_toolbar.png", toolbar_prompt)
if t_result == ffi.NULL then flush("  VLM 工具栏识别失败\n"); t_result = ffi.new("char[1]") end
local t_text = ffi.string(t_result)
flush("  VLM: " .. t_text:gsub("\n", " | ") .. "\n")

-- 解析 VLM 名称
local t_names = {}
for line in t_text:gmatch("[^\n]+") do
    local name = line:match("^%d+%.%s*(%w+)")
    if name then table.insert(t_names, name) end
end

-- CC 检测
local t_boxes = detect_boxes("/tmp/calib_toolbar.png", col3.w, tool_h)
table.sort(t_boxes, function(a,b) return a.x < b.x end)
flush(string.format("  CC 检测到 %d 个组件\n", #t_boxes))

local toolbar_icons = {}
for i, name in ipairs(t_names) do
    local b = t_boxes[i]
    if b then
        local entry = icon_actions.lookup(name)
        table.insert(toolbar_icons, {
            name    = name,
            name_cn = (entry and entry.name_cn) or name,
            rel_x   = math.floor(b.cx + col3.x),
            rel_y   = math.floor(b.cy + tool_y),
            w       = b.w,
            h       = b.h,
        })
        flush(string.format("  %d. %-12s → (%3d, %3d)\n", i, name, math.floor(b.cx + col3.x), math.floor(b.cy + tool_y)))
    end
end
-- 多余 CC 组件也加进去（VLM 没提到的右边图标）
local extra_fallback = {"Send", "MiniProgram"}
for i = #t_names + 1, math.min(#t_boxes, #t_names + #extra_fallback) do
    local b = t_boxes[i]
    if b then
        local name = extra_fallback[i - #t_names]
        table.insert(toolbar_icons, {
            name    = name,
            name_cn = name,
            rel_x   = math.floor(b.cx + col3.x),
            rel_y   = math.floor(b.cy + tool_y),
            w       = b.w,
            h       = b.h,
        })
        flush(string.format("  %d. %-12s → (%3d, %3d) [extra]\n", i, name, math.floor(b.cx + col3.x), math.floor(b.cy + tool_y)))
    end
end

-- ==== 3. 第三列顶部（通话/菜单按钮，只识别不标注） ====
flush("\n[3/3] VLM 识别第三列顶部图标...\n")
local top_y = 0
local top_h = 55
os.execute(string.format("convert '/tmp/calib_full.png' +repage -crop %dx%d+%d+%d '/tmp/calib_top.png' 2>/dev/null",
    col3.w, top_h, col3.x, top_y))

local top_prompt = [[List icons in the top-right of WeChat chat window, left to right.
Possible: Phone, Camera, Menu.
Format: "1. Phone"]]
local top_result = lib.joycaption_analyze("/tmp/calib_top.png", top_prompt)
if top_result ~= ffi.NULL then
    local top_text = ffi.string(top_result)
    flush("  VLM: " .. top_text:gsub("\n", " | ") .. "\n")
    local top_names = {}
    for line in top_text:gmatch("[^\n]+") do
        local name = line:match("^%d+%.%s*(%w+)")
        if name then table.insert(top_names, name) end
    end
    local top_boxes = detect_boxes("/tmp/calib_top.png", col3.w, top_h)
    local right_boxes = {}
    for _, b in ipairs(top_boxes) do
        if b.cx > col3.w * 0.5 then table.insert(right_boxes, b) end
    end
    table.sort(right_boxes, function(a,b) return a.x < b.x end)
    local top_icons = {}
    for i, name in ipairs(top_names) do
        local b = right_boxes[i]
        if b then
            local entry = icon_actions.lookup(name)
            table.insert(top_icons, {
                name    = name,
                name_cn = (entry and entry.name_cn) or name,
                rel_x   = math.floor(b.cx + col3.x),
                rel_y   = math.floor(b.cy + top_y),
                w       = b.w,
                h       = b.h,
                no_annotate = true,
            })
            flush(string.format("  %d. %-12s → (%3d, %3d)\n", i, name, math.floor(b.cx + col3.x), math.floor(b.cy + top_y)))
        end
    end
end

-- 释放 VLM
lib.joycaption_free()
flush("  VLM 已释放\n\n")

-- ==== 4. 保存 ====
local cjson = require("cjson")
local config = {
    window = { w = win.w, h = win.h },
    sidebar  = sidebar_icons,
    toolbar  = toolbar_icons,
    top      = top_icons or {},
    calibrated_at = os.date("%Y-%m-%dT%H:%M:%S"),
}
local home = os.getenv("HOME")
local f = io.open(home .. "/.wechat_icons.json", "w")
if f then
    f:write(cjson.encode(config))
    f:close()
    flush(string.format("✅ 已保存 %d 个图标到 ~/.wechat_icons.json\n", #sidebar_icons + #toolbar_icons))
else
    flush("❌ 写入失败\n")
    os.exit(1)
end

-- ==== 4. 画标注图 ====
flush("\n[4/4] 生成标注图...\n")
local anno = "/tmp/calib_anno.png"
os.execute(string.format("convert '/tmp/calib_full.png' +repage '%s' 2>/dev/null", anno))

local font = "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"

-- 合并所有图标，分配数字编号
local all_icons = {}
for _, icon in ipairs(sidebar_icons) do
    table.insert(all_icons, { num = #all_icons + 1, icon = icon, color = "lime", area = "Sidebar" })
end
for _, icon in ipairs(toolbar_icons) do
    table.insert(all_icons, { num = #all_icons + 1, icon = icon, color = "dodgerblue", area = "Toolbar" })
end


-- 在图标上画数字（跳过 no_annotate）
for _, item in ipairs(all_icons) do
    if not item.icon.no_annotate then
    local ic = item.icon
    local x1 = ic.rel_x - math.floor(ic.w / 2) - 2
    local y1 = ic.rel_y - math.floor(ic.h / 2) - 2
    local x2 = x1 + ic.w + 4
    local y2 = y1 + ic.h + 4
    local fill = item.color == "lime" and "rgba(0,255,0,0.2)" or "rgba(30,144,255,0.2)"
    local stroke = item.color
    os.execute(string.format("convert '%s' -fill '%s' -draw 'rectangle %d,%d %d,%d' '%s' 2>/dev/null", anno, fill, x1, y1, x2, y2, anno))
    os.execute(string.format("convert '%s' -fill none -stroke '%s' -strokewidth 2 -draw 'rectangle %d,%d %d,%d' '%s' 2>/dev/null", anno, stroke, x1, y1, x2, y2, anno))
    -- 数字标记在图标右下角
    local nx = x2 - 14
    local ny = y2 - 2
    os.execute(string.format("convert '%s' -fill 'rgba(0,0,0,0.7)' -draw 'rectangle %d,%d %d,%d' '%s' 2>/dev/null", anno, nx - 2, ny - 14, nx + 16, ny + 2, anno))
    os.execute(string.format("convert '%s' -fill white -font '%s' -pointsize 13 -annotate +%d+%d '%d' '%s' 2>/dev/null", anno, font, nx, ny, item.num, anno))
    end
end

-- 图例表放在第二列（聊天列表区顶部）
local lx = COL1 + 10
local ly = 10
local line_h = 22
local total_lines = #all_icons + 2  -- 标题 + 分隔 + 条目

-- 图例背景
local bg_h = total_lines * line_h + 12
os.execute(string.format("convert '%s' -fill 'rgba(0,0,0,0.6)' -draw 'rectangle %d,%d %d,%d' '%s' 2>/dev/null",
    anno, lx, ly, lx + 185, ly + bg_h, anno))

-- 标题
local ty = ly + 17
os.execute(string.format("convert '%s' -fill white -font '%s' -pointsize 14 -annotate +%d+%d 'Icon Legend' '%s' 2>/dev/null",
    anno, font, lx + 10, ty, anno))

-- 每个条目（跳过 no_annotate）
for _, item in ipairs(all_icons) do
    if item.icon.no_annotate then goto continue end
    local ey = ly + 12 + (item.num + 1) * line_h
    local color = item.color
    -- 小色块
    os.execute(string.format("convert '%s' -fill '%s' -draw 'rectangle %d,%d %d,%d' '%s' 2>/dev/null",
        anno, color, lx + 10, ey - 12, lx + 24, ey + 2, anno))
    -- 编号 + 英文名
    local text = string.format("%d. %s", item.num, item.icon.name)
    os.execute(string.format("convert '%s' -fill white -font '%s' -pointsize 13 -annotate +%d+%d '%s' '%s' 2>/dev/null",
        anno, font, lx + 30, ey, text, anno))
    ::continue::
end

local final_anno = home .. "/wechat_icons_annotated.png"
os.execute(string.format("cp '%s' '%s'", anno, final_anno))
flush(string.format("✅ %s\n", final_anno))
