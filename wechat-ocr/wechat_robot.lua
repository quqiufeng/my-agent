-- WeChat Robot Library
-- 基于测试验证的微信自动化操作库
-- 用法: local robot = require("wechat_robot")
-- 依赖: wechat_ocr + xdotool + xclip
--
-- 录像功能: 默认关闭，M.set_record(true) 开启
--           M.set_record(false) 关闭
--           M.set_record_output("path.mp4") 指定输出文件

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

ffi.cdef[[
    int         joycaption_init(const char* model, const char* mmproj, int use_gpu);
    const char* joycaption_analyze(const char* image, const char* prompt);
    void        joycaption_free();
    int         joycaption_is_initialized();
]]

local ocr = require("wechat_ocr")
local dir = "/opt/my-agent/wechat-ocr"

local cjson = require("cjson")

local M = {}
local _recording_pid = nil
local _record_enabled = false
local _record_output = "/tmp/wx_robot_record.mp4"

-- === 录像控制 ===

function M.set_record(on)
    _record_enabled = on
end

function M.set_record_output(path)
    _record_output = path
end

function M.get_record()
    return _record_enabled
end

local function start_recording()
    if not _record_enabled then return end
    local cmd = string.format(
        "ffmpeg -y -f x11grab -r 10 -s 2560x1440 -i :0.0 "
        .. "-vcodec libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p "
        .. "'%s' & echo $!", _record_output)
    local f = io.popen(cmd, "r")
    if f then
        local pid = f:read("*a"); f:close()
        _recording_pid = pid:match("%d+")
        ffi.C.usleep(1000000)
    end
end

local function stop_recording()
    if _recording_pid then
        os.execute("kill " .. _recording_pid .. " 2>/dev/null")
        _recording_pid = nil
    end
end

-- 初始化（加载OCR模型）
function M.init()
    local ok, err = ocr.init(
        dir.."/models/ch_PP-OCRv4_det_infer.onnx",
        dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
        dir.."/ppocr_keys_v1.txt")
    if ok and _record_enabled then
        start_recording()
    end
    return ok, err
end

-- 销毁
function M.destroy()
    if _record_enabled then stop_recording() end
    ocr.destroy()
end

-- ======== 窗口工具 ========

function M.activate()
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    ffi.C.usleep(500000)
end

function M.get_window_rect()
    os.execute("xdotool getactivewindow getwindowgeometry > /tmp/wx_rect.txt 2>/dev/null")
    local f = io.open("/tmp/wx_rect.txt")
    local geo = f:read("*a"); f:close()
    local _, _, wx = geo:find("Position: (%d+)")
    local _, _, wy = geo:find(",(%d+)")
    local _, _, ww = geo:find("Geometry: (%d+)")
    local _, _, wh = geo:find("x(%d+)")
    if not wx then return nil end
    return {x=tonumber(wx), y=tonumber(wy), w=tonumber(ww), h=tonumber(wh)}
end

-- ======== OCR 语义定位 ========

function M.find_text(target)
    local data, err = ocr.capture_raw()
    if not data then return nil, err end
    local boxes = data.boxes or {}
    for _, b in ipairs(boxes) do
        if b.text == target then
            local cx = math.floor(b.x + b.w / 2)
            local cy = math.floor(b.y + b.h / 2)
            return {x = cx, y = cy, box = b}
        end
    end
    return nil, "not found: " .. target
end

function M.find_texts(target, limit)
    limit = limit or 10
    local data, err = ocr.capture_raw()
    if not data then return nil, err end
    local results = {}
    local boxes = data.boxes or {}
    for _, b in ipairs(boxes) do
        if b.text == target and #results < limit then
            table.insert(results, {
                x = math.floor(b.x + b.w / 2),
                y = math.floor(b.y + b.h / 2),
                box = b
            })
        end
    end
    return results
end

function M.find_text_partial(partial)
    local data, err = ocr.capture_raw()
    if not data then return nil, err end
    local boxes = data.boxes or {}
    for _, b in ipairs(boxes) do
        if b.text:find(partial, 1, true) then
            local cx = math.floor(b.x + b.w / 2)
            local cy = math.floor(b.y + b.h / 2)
            return {x = cx, y = cy, box = b}
        end
    end
    return nil, "not found: " .. partial
end

function M.click_text(target)
    local pos, err = M.find_text(target)
    if not pos then return false, err end
    M.activate()
    ffi.C.usleep(200000)
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", pos.x, pos.y))
    ffi.C.usleep(500000)
    return true
end

function M.click_text_partial(partial)
    local pos, err = M.find_text_partial(partial)
    if not pos then return false, err end
    M.activate()
    ffi.C.usleep(200000)
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", pos.x, pos.y))
    ffi.C.usleep(500000)
    return true
end

-- ======== 消息 ========

function M.capture()
    return ocr.capture()
end

function M.send(text)
    return ocr.send(text)
end

-- ======== 发送文件 ========

function M.send_file(filepath)
    M.activate()
    local data = ocr.capture_raw()
    if not data then return false, "OCR failed" end
    local col3 = data.win.x
    local input_y = data.win.y + data.win.h - 175
    local icon_x = col3 + 130
    local icon_y = input_y - 40
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", icon_x, icon_y))
    ffi.C.usleep(800000)
    local filename = filepath:match("([^/]+)$")
    local f = io.open("/tmp/wx_send_file.txt", "w")
    f:write(filename); f:close()
    os.execute("xclip -selection clipboard < /tmp/wx_send_file.txt 2>/dev/null")
    ffi.C.usleep(100000)
    os.execute("xdotool key ctrl+v 2>/dev/null")
    ffi.C.usleep(500000)
    os.execute("xdotool key Return 2>/dev/null")
    ffi.C.usleep(2000000)
    os.execute("xdotool key Return 2>/dev/null")
    return true
end

-- ======== 截图 ========

function M.screenshot()
    M.activate()
    local data = ocr.capture_raw()
    if not data then return false end
    local col3 = data.win.x
    local input_y = data.win.y + data.win.h - 175
    local icon_x = col3 + 130 + 38
    local icon_y = input_y - 40
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", icon_x, icon_y))
    ffi.C.usleep(500000)
    os.execute("xdotool mousemove 0 0 2>/dev/null")
    ffi.C.usleep(100000)
    os.execute("xdotool mousedown 1 2>/dev/null")
    ffi.C.usleep(100000)
    os.execute("xdotool mousemove 2560 1440 2>/dev/null")
    ffi.C.usleep(300000)
    os.execute("xdotool mouseup 1 2>/dev/null")
    ffi.C.usleep(300000)
    os.execute("xdotool mousemove 1280 720 2>/dev/null")
    ffi.C.usleep(200000)
    os.execute("xdotool click 1 2>/dev/null")
    ffi.C.usleep(200000)
    os.execute("xdotool click 1 2>/dev/null")
    ffi.C.usleep(500000)
    os.execute("xdotool key Return 2>/dev/null")
    return true
end

-- ======== 搜索 ========

function M.search(keyword)
    keyword = keyword or "小王"
    M.activate()

    -- OCR 优先：直接点击联系人名称
    local pos, err = M.find_text_partial(keyword)
    if pos then
        os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", pos.x, pos.y))
        ffi.C.usleep(500000)
        return true
    end

    -- 找不到联系人，回退搜索框
    local win = M.get_window_rect()
    if not win then return false end
    local sx = win.x + 180
    local sy = win.y + 50
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", sx, sy))
    ffi.C.usleep(500000)
    local f = io.open("/tmp/wx_search.txt", "w")
    f:write(keyword); f:close()
    os.execute("xclip -selection clipboard < /tmp/wx_search.txt 2>/dev/null")
    ffi.C.usleep(100000)
    os.execute("xdotool key ctrl+v 2>/dev/null")
    ffi.C.usleep(300000)
    os.execute("xdotool key Return 2>/dev/null")
    return true
end

-- ======== 通讯录 ========

function M.contacts_search(keyword)
    keyword = keyword or "小王"
    M.activate()

    -- OCR 优先：直接点击联系人名称
    local pos, err = M.find_text_partial(keyword)
    if pos then
        os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", pos.x, pos.y))
        ffi.C.usleep(500000)
        return true
    end

    -- 点击通讯录图标 → 搜索框搜索
    local win = M.get_window_rect()
    if not win then return false end
    local icon_x = win.x + 40
    local icon_y = win.y + 110 + 60
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", icon_x, icon_y))
    ffi.C.usleep(800000)
    local sx = win.x + 160
    local sy = win.y + 50
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", sx, sy))
    ffi.C.usleep(500000)
    local f = io.open("/tmp/wx_contact_search.txt", "w")
    f:write(keyword); f:close()
    os.execute("xclip -selection clipboard < /tmp/wx_contact_search.txt 2>/dev/null")
    ffi.C.usleep(100000)
    os.execute("xdotool key ctrl+v 2>/dev/null")
    ffi.C.usleep(300000)
    os.execute("xdotool key Return 2>/dev/null")
    return true
end

-- ======== 侧边栏 ========

function M.click_sidebar(index)
    index = index or 1
    M.activate()
    local win = M.get_window_rect()
    if not win then return false end
    local icon_x = win.x + 40
    local icon_y = win.y + 110 + (index - 1) * 60
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", icon_x, icon_y))
    ffi.C.usleep(800000)
    return true
end

-- ======== 图标识别（ImageMagick + VLM） ========

local _vlm_lib = nil
local _icon_cache = nil

local VLM_MODEL  = "/data/models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"
local VLM_MMPROJ = "/data/models/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf"

local function vlm_load()
    if _vlm_lib then return true end
    local lib_paths = {
        "libjoycaption",
        "/opt/my-agent/joycaption-wrapper/libjoycaption.so",
        os.getenv("HOME") .. "/my-agent/joycaption-wrapper/libjoycaption.so",
    }
    local lib
    for _, p in ipairs(lib_paths) do
        local ok, l = pcall(ffi.load, p)
        if ok then lib = l; break end
    end
    if not lib then return false, "libjoycaption.so not found in any path" end
    local ret = lib.joycaption_init(VLM_MODEL, VLM_MMPROJ, 1)
    if ret ~= 0 then return false, "VLM init failed" end
    _vlm_lib = lib
    return true
end

-- 检测第一列图标 + VLM 语义识别
function M.scan_icons()
    local ok, err = vlm_load()
    if not ok then return nil, err end

    M.activate()

    -- 窗口几何
    local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
    local wx = tonumber(geo:match("Position: (%d+)"))
    local wy = tonumber(geo:match(",(%d+)"))
    local ww = tonumber(geo:match("Geometry: (%d+)"))
    local wh = tonumber(geo:match("x(%d+)"))
    if not wx then return nil, "no window" end

    -- 截图
    os.execute(string.format("import -window root -crop %dx%d+%d+%d '/tmp/wx_scan_raw.png' 2>/dev/null", ww, wh, wx, wy))

    -- 检测第一列宽度
    local COL1 = 75
    local bg_pipe = io.popen(string.format(
        "convert '/tmp/wx_scan_raw.png' +repage -crop 8x8+0+0 -colorspace gray -format '%%[fx:mean*255]' info: 2>/dev/null"))
    local bg_val = 237
    if bg_pipe then
        local s = bg_pipe:read("*a"); bg_pipe:close()
        bg_val = tonumber(s:match("[%d.]+")) or bg_val
    end
    local proj_cmd = string.format(
        "convert '/tmp/wx_scan_raw.png' +repage -crop 120x%d+0+0 -colorspace gray " ..
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

    -- Connected components 检测
    local all_lines = {}
    for _, thr in ipairs({5, 10, 20, 30}) do
        local cmd = string.format(
            "convert '/tmp/wx_scan_raw.png' +repage -crop %dx%d+0+0 -colorspace gray -canny 0x1+%d%%%%+%d%%%% " ..
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
            "convert '/tmp/wx_scan_raw.png' +repage -crop %dx%d+0+0 -colorspace gray " ..
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
            if dx*dx + dy*dy < 900 then
                dup = true; break
            end
        end
        if not dup then table.insert(merged, b) end
    end
    table.sort(merged, function(a,b) return a.y < b.y end)

    -- VLM 识别
    local col1_file = "/tmp/wx_scan_col1.png"
    os.execute(string.format("convert '/tmp/wx_scan_raw.png' +repage -crop %dx%d+0+0 '%s' 2>/dev/null", COL1, wh, col1_file))
    local prompt = [[You are looking at the left sidebar of WeChat. List each icon you see in order from top to bottom. For each one, give:
- Icon number (1, 2, 3...)
- What it represents (e.g., "Chats", "Contacts", "Discover", "Moments", "Me", "Settings", "Wallet", "More")
- Brief visual description
Format: "1. Chats - speech bubble icon"]]
    local text = _vlm_lib.joycaption_analyze(col1_file, prompt)
    if text == ffi.NULL then return nil, "VLM returned null" end
    local result = ffi.string(text)

    -- 解析 LLM 输出
    local icon_actions = require("icon_actions")
    local icons = {}
    for line in result:gmatch("[^\n]+") do
        local name, desc = line:match("^%d+%.%s*(%w+)%s*[-–—]%s*(.+)$")
        if not name then name = line:match("^%d+%.%s*(%w+)") end
        if name then
            local ok_entry, entry = pcall(icon_actions.verify, name, desc)
            local entry_ok = ok_entry and entry
            table.insert(icons, {
                name     = name,
                desc     = desc or "",
                name_cn  = entry_ok and entry.name_cn or name,
                name_en  = entry_ok and entry.name_en or name,
                action   = entry_ok and entry.desc or "",
                matched  = (entry_ok ~= nil),
                pos      = nil, -- will match to y below
            })
        end
    end

    -- 匹配 LLM 名次和实际 y 坐标（取最近的框）
    for _, icon in ipairs(icons) do
        local best_dist = 99999
        local best_box = nil
        for _, b in ipairs(merged) do
            local dist = math.abs(b.cy - (icon._y or 0))
            if dist < best_dist then
                best_dist = dist
                best_box = b
            end
        end
        if best_box then
            icon.pos = {
                x = wx + math.floor(best_box.x + best_box.w / 2),
                y = wy + math.floor(best_box.y + best_box.h / 2),
                w = best_box.w,
                h = best_box.h,
            }
        end
    end

    _icon_cache = icons
    return icons
end

-- 按名称获取图标位置
function M.get_icon(name)
    if not _icon_cache then
        local icons, err = M.scan_icons()
        if not icons then return nil, err end
    end
    for _, icon in ipairs(_icon_cache) do
        if icon.name == name or icon.name_cn == name or icon.name_en == name then
            return icon
        end
    end
    return nil, "icon not found: " .. tostring(name)
end

-- 按名称点击图标
function M.click_icon(name)
    local icon, err = M.get_icon(name)
    if not icon then return false, err end
    if not icon.pos then return false, "icon has no position" end
    M.activate()
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", icon.pos.x, icon.pos.y))
    ffi.C.usleep(500000)
    return true
end

-- 清理 VLM 资源
function M.vlm_free()
    if _vlm_lib then
        _vlm_lib.joycaption_free()
        _vlm_lib = nil
        _icon_cache = nil
    end
end

-- ======== 监控 ========

function M.monitor(opts)
    opts = opts or {}
    -- 如果开启录像且monitor未特别关闭录像
    if _record_enabled and opts.record ~= false then
        start_recording()
    end
    local function wrapped_on_msg(text, cycle)
        if opts.on_message then opts.on_message(text, cycle) end
    end
    local function wrapped_on_init(text)
        if opts.on_initial then opts.on_initial(text) end
    end
    local ok, err = pcall(ocr.monitor, {
        interval_ms = opts.interval_ms or 3000,
        on_message = wrapped_on_msg,
        on_initial = wrapped_on_init,
        on_error = opts.on_error,
    })
    if _record_enabled then stop_recording() end
    if not ok then error(err) end
end

-- ======== 手动录屏 ========

function M.start_recording(output, duration)
    if _record_enabled then
        -- 使用_set_record模式，不额外录
        return _recording_pid
    end
    local out = output or "/tmp/wx_record.mp4"
    local cmd = string.format(
        "ffmpeg -y -f x11grab -r 10 -s 2560x1440 -i :0.0 "
        .. "-vcodec libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p "
        .. "-t %d '%s' & echo $!", duration or 15, out)
    local f = io.popen(cmd, "r")
    if f then
        local pid = f:read("*a"); f:close()
        _recording_pid = pid:match("%d+")
        ffi.C.usleep(1000000)
    end
    return _recording_pid
end

function M.stop_recording()
    stop_recording()
end

return M
