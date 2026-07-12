#!/usr/bin/env luajit
-- ============================================================
-- 第一列图标 → LLM 识别（libjoycaption.so）
-- ============================================================
-- 用法:
--   cd /opt/my-agent/wechat-ocr
--   export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib:/opt/my-agent/joycaption-wrapper
--   export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
--   export LUA_CPATH="/usr/local/lualib/?.so;;"
--   luajit tests/test_llm_icons.lua
-- ============================================================

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
    const char*   ocr_last_error(ocr_engine_t*);
]]

ffi.cdef[[
    int         joycaption_init(const char* model, const char* mmproj, int use_gpu);
    const char* joycaption_analyze(const char* image, const char* prompt);
    void        joycaption_free();
    int         joycaption_is_initialized();
]]

local function printf(fmt, ...)
    io.write(string.format(fmt, ...))
    io.flush()
end

-- ---------------------------------------------------------------
-- 配置
-- ---------------------------------------------------------------
local MODEL = "/data/models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"
local MMPROJ = "/data/models/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf"

-- ---------------------------------------------------------------
-- 1. 截图 + 图标检测（同 test_first_icons.lua）
-- ---------------------------------------------------------------
local function capture_and_detect()
    -- 激活微信
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    ffi.C.usleep(500000)

    -- 窗口几何
    local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
    local wx = tonumber(geo:match("Position: (%d+)"))
    local wy = tonumber(geo:match(",(%d+)"))
    local ww = tonumber(geo:match("Geometry: (%d+)"))
    local wh = tonumber(geo:match("x(%d+)"))
    if not wx then printf("❌ 获取窗口失败\n"); return nil end

    printf("窗口: (%d,%d) %dx%d\n", wx, wy, ww, wh)

    -- 截图
    os.execute(string.format("import -window root -crop %dx%d+%d+%d '/tmp/wx_first_raw.png' 2>/dev/null", ww, wh, wx, wy))

    -- OCR 获取第三列边界 (optional)
    local col2_rel = 0
    local lib = ffi.load("libwechat_ocr_core.so")
    local engine = lib.ocr_create(
        "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_det_infer.onnx",
        "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_rec_infer.onnx",
        "/opt/my-agent/wechat-ocr/ppocr_keys_v1.txt")
    if engine and engine ~= ffi.NULL then
        local s = lib.ocr_capture(engine)
        if s and s ~= ffi.NULL then
            local d = cjson.decode(ffi.string(s))
            lib.ocr_free_string(s)
            col2_rel = d.win.x - wx
        end
        lib.ocr_destroy(engine)
    end

    -- 第一列宽度检测
    local COL1 = 75
    local bg_val = 237
    local bg_pipe = io.popen(string.format(
        "convert '/tmp/wx_first_raw.png' +repage -crop 8x8+0+0 -colorspace gray -format '%%[fx:mean*255]' info: 2>/dev/null"))
    if bg_pipe then
        local s = bg_pipe:read("*a"); bg_pipe:close()
        bg_val = tonumber(s:match("[%d.]+")) or bg_val
    end
    local proj_cmd = string.format(
        "convert '/tmp/wx_first_raw.png' +repage -crop 120x%d+0+0 -colorspace gray " ..
        "-fx 'abs(u - %d/255) > 0.04' -scale 1x%d! -scale 120x%d! " ..
        "txt:- 2>/dev/null | awk -F'[,:]' '/#FFFFFF/{print $1}' | sort -rn | head -1",
        wh, bg_val, wh, wh)
    local spipe = io.popen(proj_cmd, "r")
    if spipe then
        local last_col = spipe:read("*a"):match("(%d+)")
        spipe:close()
        if last_col then
            local detected = tonumber(last_col) + 5
            if detected >= 30 and detected <= 110 then COL1 = detected end
        end
    end
    printf("第一列宽度: %dpx\n", COL1)

    -- Connected components 检测
    local all_lines = {}
    for _, thr in ipairs({5, 10, 20, 30}) do
        local cmd = string.format(
            "convert '/tmp/wx_first_raw.png' +repage -crop %dx%d+0+0 -colorspace gray -canny 0x1+%d%%%%+%d%%%% " ..
            "-negate -define connected-components:verbose=true -connected-components 4 /dev/null 2>&1 " ..
            "| grep -v 'bgcolor\\|id:\\|0:.*gray'",
            COL1, wh, thr, thr * 2)
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
    for _, sep in ipairs({2, 4, 6, 10}) do
        local diff = sep * 100 / 255
        local cmd = string.format(
            "convert '/tmp/wx_first_raw.png' +repage -crop %dx%d+0+0 -colorspace gray " ..
            "-fx 'abs(u - %d/255)' -threshold %.1f%%%% " ..
            "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1 " ..
            "| grep -v 'bgcolor\\|id:\\|0:.*gray'",
            COL1, wh, bg_val, diff)
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

    local tmp = {}
    for _, b in ipairs(all_lines) do
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
            if dx*dx + dy*dy < 900 then  -- 半径 ~30px
                dup = true; break
            end
        end
        if not dup then table.insert(merged, b) end
    end
    table.sort(merged, function(a,b) return a.y < b.y end)

    printf("检测到 %d 个图标\n", #merged)

    -- 保存带有标注框的标记图
    local ts = os.date("%Y%m%d_%H%M%S")
    local outfile = os.getenv("HOME") .. "/wechat_first_icons_" .. ts .. ".png"
    local cmds = {
        '-fill none -stroke "rgb(0,0,255)" -strokewidth 2 -draw "line ' .. COL1 .. ',0 ' .. COL1 .. ',' .. wh .. '"'
    }
    for i, b in ipairs(merged) do
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
    printf("标记图: %s\n", outfile)

    -- 裁第一列（供 LLM 识别）
    local col1_file = "/tmp/wx_col1_" .. ts .. ".png"
    os.execute(string.format("convert '/tmp/wx_first_raw.png' -crop %dx%d+0+0 '%s' 2>/dev/null", COL1, wh, col1_file))

    return {
        col1_file = col1_file,
        icons = merged,
        COL1 = COL1,
        wh = wh,
        ww = ww,
        wx = wx,
        wy = wy,
    }
end

-- ---------------------------------------------------------------
-- 2. LLM 识别
-- ---------------------------------------------------------------
local function load_llm()
    local lib = ffi.load("libjoycaption")
    printf("加载 LLM...\n")
    local ret = lib.joycaption_init(MODEL, MMPROJ, 1)
    if ret ~= 0 then
        printf("❌ LLM 初始化失败\n")
        return nil
    end
    printf("✅ LLM 加载完成\n")
    return lib
end

local function identify_icons(lib, result)
    local prompt = [[You are looking at the left sidebar of WeChat (微信). This image shows icons in the left navigation bar from top to bottom.
List each icon you see in order from top to bottom. For each one, give:
- Icon number (1, 2, 3...)
- What you think it represents (e.g., "Chats", "Contacts", "Discover", etc.)
- Brief visual description of the icon

Format: "1. Chats - speech bubble icon"
        ]]
    printf("发送到 LLM 识别...\n")
    local text = lib.joycaption_analyze(result.col1_file, prompt)
    if text == ffi.NULL then
        printf("❌ LLM 返回空\n")
        return
    end
    local s = ffi.string(text)
    printf("=== LLM 识别结果 ===\n")
    print(s)

    -- 保存结果
    local fh = io.open("/tmp/llm_icon_result.txt", "w")
    if fh then
        fh:write(s)
        fh:close()
    end

    return text  -- 返回给 map_icons 用
end

-- ---------------------------------------------------------------
-- 3. 识别结果 → 功能映射
-- ---------------------------------------------------------------
local function map_icons(llm_text, detected_icons)
    local ok, icon_actions = pcall(require, "icon_actions")
    if not ok then
        printf("⚠️  icon_actions 模块未找到，跳过映射\n")
        return {}
    end
    local results = {}
    for line in llm_text:gmatch("[^\n]+") do
        local name, desc = line:match("^%d+%.%s*(%w+)%s*[-–—]%s*(.+)$")
        if not name then
            name = line:match("^%d+%.%s*(%w+)")
        end
        if name then
            -- 找最近的 y 坐标（去重合并用）
            local ok, entry = icon_actions.verify(name, desc)
            table.insert(results, {
                raw_name = name,
                raw_desc = desc or "",
                name_cn  = entry and entry.name_cn or "?" .. name,
                name_en  = entry and entry.name_en or name,
                desc     = entry and entry.desc or "",
                matched  = ok,
            })
        end
    end

    printf("\n=== 功能映射 ===\n")
    for _, r in ipairs(results) do
        local tag = r.matched and "✅" or "❓"
        printf("  %s %-12s → %s  (%s)\n", tag, r.raw_name, r.name_cn, r.desc)
    end
    return results
end

-- ---------------------------------------------------------------
-- 4. 逐图标识别（可选）
-- ---------------------------------------------------------------
local function identify_each_icon(lib, result)
    local ts = os.date("%Y%m%d_%H%M%S")
    printf("\n逐图标识别...\n")
    for i, b in ipairs(result.icons) do
        local crop = string.format("/tmp/icon_%d_%s.png", i, ts)
        -- 裁小图 & 放大到 224x224 确保模型能看清
        os.execute(string.format("convert '/tmp/wx_first_raw.png' +repage -crop %dx%d+%d+%d -resize 224x224 '%s' 2>/dev/null",
            b.w, b.h, b.x, b.y, crop))
        local prompt = "Describe the icon in this image. What does it represent? Answer in 2-3 words."
        local text = lib.joycaption_analyze(crop, prompt)
        local s = "error"
        if text and text ~= ffi.NULL then
            s = ffi.string(text):gsub("\n", " "):gsub("\r", "")
        end
        printf("  图标 %2d (y=%d): %s\n", i, b.y, s)
    end
end

-- ---------------------------------------------------------------
-- 主流程
-- ---------------------------------------------------------------
printf("=== 图标检测 + LLM 识别 ===\n\n")

local result = capture_and_detect()
if not result then
    printf("❌ 截图/检测失败\n")
    os.exit(1)
end

printf("\n--- LLM 识别 ---\n")
local lib = load_llm()
if lib then
    local text_ptr = identify_icons(lib, result)
    if text_ptr then
        local text_str = ffi.string(text_ptr)
        map_icons(text_str, result.icons)
    end
    identify_each_icon(lib, result)
    lib.joycaption_free()
end

os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
printf("\n完成\n")
