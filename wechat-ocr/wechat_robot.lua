-- WeChat Robot Library
-- 基于已验证测试脚本重构，使用坐标缓存 + 窗口左上角动态计算
-- 用法: local robot = require("wechat_robot")
--
-- 流式调用示例:
--   robot:search("小王"):send("你好"):send_file("a.mp4"):screenshot()

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]
ffi.cdef[[int getpid(void);]]

local ocr = require("wechat_ocr")
local cjson = require("cjson")
local dir = "/opt/my-agent/wechat-ocr"

local M = {}

-- === 状态 ===
local _recording_pid = nil
local _record_enabled = false
local _record_output = "/tmp/wx_robot_record.mp4"
local _icon_cache = nil

-- === 常量 ===
local HOME = os.getenv("HOME") or "/tmp"
local ICON_CACHE_PATHS = {
    dir .. "/wechat_icons.json",
    HOME .. "/.wechat_icons.json",
}

local SIDEBAR_INDEX_MAP = {
    [1] = "WeChat",
    [2] = "Contacts",
    [3] = "Favorites",
    [4] = "Moments",
    [5] = "Channels",
    [6] = "Search",
    [7] = "MiniProgram",
}

-- === 基础工具 ===

local function sleep(us)
    ffi.C.usleep(us)
end

local function flush(s)
    io.write(s or ""); io.flush()
end

local function shell_escape(s)
    return s:gsub("'", "'\\''")
end

local function type_text(text, delay_ms)
    delay_ms = delay_ms or 80
    os.execute(string.format("xdotool type --delay %d '%s' 2>/dev/null", delay_ms, shell_escape(text)))
end

function M.activate()
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    sleep(500000)
    return M
end

function M.get_window_rect()
    os.execute("xdotool getactivewindow getwindowgeometry > /tmp/wx_rect.txt 2>/dev/null")
    local f = io.open("/tmp/wx_rect.txt")
    if not f then return nil end
    local geo = f:read("*a"); f:close()
    local wx = tonumber(geo:match("Position: (%d+)"))
    local wy = tonumber(geo:match(",(%d+)"))
    local ww = tonumber(geo:match("Geometry: (%d+)"))
    local wh = tonumber(geo:match("x(%d+)"))
    if not wx then return nil end
    return {x = wx, y = wy, w = ww, h = wh}
end

-- === 图标缓存加载 ===

local function load_icons()
    if _icon_cache then return _icon_cache end
    for _, path in ipairs(ICON_CACHE_PATHS) do
        local f = io.open(path, "r")
        if f then
            local s = f:read("*a"); f:close()
            local ok, data = pcall(cjson.decode, s)
            if ok and data then
                _icon_cache = data
                return data
            end
        end
    end
    return nil
end

function M.reload_icons()
    _icon_cache = nil
    return load_icons()
end

function M.get_icon_pos(name, area)
    local data = load_icons()
    if not data then return nil, "no icon cache" end
    local list = data[area or "toolbar"]
    if not list then return nil, "area not found: " .. tostring(area) end
    for _, icon in ipairs(list) do
        if icon.name == name or icon.name_cn == name then
            M.activate()
            local win = M.get_window_rect()
            if not win then return nil, "no window" end
            return {
                x = win.x + icon.rel_x,
                y = win.y + icon.rel_y,
                rel_x = icon.rel_x,
                rel_y = icon.rel_y,
                w = icon.w,
                h = icon.h,
            }
        end
    end
    return nil, "icon not found: " .. tostring(name)
end

function M.click_icon(name, area)
    local pos, err = M.get_icon_pos(name, area)
    if not pos then
        io.stderr:write("[wechat_robot] click_icon failed: " .. tostring(err) .. "\n")
        return M
    end
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", pos.x, pos.y))
    sleep(500000)
    return M
end

-- === 初始化 / 销毁 ===

function M.set_record(on)
    _record_enabled = on
    return M
end

function M.set_record_output(path)
    _record_output = path
    return M
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
        sleep(1000000)
    end
end

local function stop_recording()
    if _recording_pid then
        os.execute("kill " .. _recording_pid .. " 2>/dev/null")
        _recording_pid = nil
    end
end

function M.init()
    local ok, err = ocr.init(
        dir .. "/models/ch_PP-OCRv4_det_infer.onnx",
        dir .. "/models/ch_PP-OCRv4_rec_infer.onnx",
        dir .. "/ppocr_keys_v1.txt")
    if ok and _record_enabled then start_recording() end
    return M
end

function M.destroy()
    if _record_enabled then stop_recording() end
    ocr.destroy()
    return M
end

-- === 核心流式操作（均返回 M，可链式调用）===

-- 搜索联系人并进入聊天
function M.search(keyword)
    keyword = keyword or "丰"
    M.activate()
    local win = M.get_window_rect()
    if not win then
        io.stderr:write("[wechat_robot] search: get window failed\n")
        return M
    end

    -- 搜索框固定位置（基于验证脚本）
    local sx = win.x + 180
    local sy = win.y + 50
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", sx, sy))
    sleep(500000)

    type_text(keyword, 300)
    sleep(300000)
    os.execute("xdotool key Return 2>/dev/null")
    sleep(1500000)
    os.execute("xdotool key Return 2>/dev/null")
    sleep(1500000)
    return M
end

-- 在当前聊天中发送文本消息
function M.send(text)
    text = text or "你好"
    M.activate()
    type_text(text, 80)
    sleep(2000000)
    os.execute("xdotool key Return 2>/dev/null")
    sleep(200000)

    -- 双保险：点发送按钮（窗口右下角固定偏移）
    local win = M.get_window_rect()
    if win then
        os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null",
            win.x + win.w - 80, win.y + win.h - 60))
        sleep(500000)
    end
    return M
end

-- 在当前聊天中发送文件（支持图片/视频/任意文件）
function M.send_file(filepath)
    filepath = filepath or "/tmp/test.txt"
    M.activate()

    local pos = M.get_icon_pos("Folder", "toolbar")
    if pos then
        os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", pos.x, pos.y))
    else
        io.stderr:write("[wechat_robot] send_file: no Folder cache, fallback\n")
        local win = M.get_window_rect()
        if not win then return M end
        local data = ocr.capture_raw()
        local col3 = data and data.win.x or win.x + 520
        os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null",
            col3 + 130, win.y + win.h - 175 - 40))
    end
    sleep(800000)
    sleep(1500000)  -- 等待文件弹窗

    type_text(filepath, 80)
    sleep(500000)
    os.execute("xdotool key Return 2>/dev/null")
    sleep(2000000)
    os.execute("xdotool key Return 2>/dev/null")
    sleep(2000000)
    return M
end

-- 在当前聊天中发送全屏截图
function M.screenshot()
    M.activate()

    local pos = M.get_icon_pos("Scissors", "toolbar")
    if not pos then
        io.stderr:write("[wechat_robot] screenshot: no Scissors cache\n")
        return M
    end

    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", pos.x, pos.y))
    sleep(800000)

    -- 框选全屏
    os.execute("xdotool mousemove 0 0 2>/dev/null")
    sleep(100000)
    os.execute("xdotool mousedown 1 2>/dev/null")
    sleep(100000)
    os.execute("xdotool mousemove 2560 1440 2>/dev/null")
    sleep(300000)
    os.execute("xdotool mouseup 1 2>/dev/null")
    sleep(500000)

    -- 双击确认
    os.execute("xdotool mousemove 1280 720 2>/dev/null")
    sleep(200000)
    os.execute("xdotool click 1 2>/dev/null")
    sleep(200000)
    os.execute("xdotool click 1 2>/dev/null")
    sleep(1000000)

    os.execute("xdotool key Return 2>/dev/null")
    sleep(1000000)
    return M
end

-- 点击侧边栏图标（1=聊天 2=通讯录 3=收藏 4=朋友圈 5=视频号 6=搜一搜 7=小程序）
function M.click_sidebar(index)
    index = index or 1
    local name = SIDEBAR_INDEX_MAP[index]
    if name then
        local ok = M.click_icon(name, "sidebar")
        if ok then return M end
    end

    -- fallback: 硬编码位置
    M.activate()
    local win = M.get_window_rect()
    if not win then return M end
    local icon_x = win.x + 40
    local icon_y = win.y + 110 + (index - 1) * 60
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", icon_x, icon_y))
    sleep(800000)
    return M
end

-- 通讯录搜索
function M.contacts_search(keyword)
    keyword = keyword or "小王"
    M.click_sidebar(2)  -- 进入通讯录

    M.activate()
    local win = M.get_window_rect()
    if not win then return M end
    local sx = win.x + 160
    local sy = win.y + 50
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", sx, sy))
    sleep(500000)

    type_text(keyword, 80)
    sleep(300000)
    os.execute("xdotool key Return 2>/dev/null")
    return M
end

-- 返回聊天列表（点击侧边栏第一个图标）
function M.return_to_chat()
    return M.click_sidebar(1)
end

-- === 未读红点检测 ===

-- 检测第二列未读消息，返回未读方块/行的坐标数组
-- 每个元素: { x, y, badge_x, badge_y, row_y, row_h }
--  x,y      : 推荐点击位置（联系人行中部）
--  badge_x,y: 红点徽章中心
function M.detect_unread()
    M.activate()
    local win = M.get_window_rect()
    if not win then return nil, "no window" end

    local wx, wy, wh = win.x, win.y, win.h
    local col1_w = 75

    -- 截图并裁出第二列
    os.execute(string.format(
        "import -window root -crop %dx%d+%d+%d '/tmp/wx_unread_full.png' 2>/dev/null",
        win.w, win.h, wx, wy))
    os.execute(string.format(
        "convert '/tmp/wx_unread_full.png' +repage -crop %dx%d+%d+0 +repage '/tmp/wx_unread_col2.png' 2>/dev/null",
        445, wh, col1_w))

    -- 垂直投影找行
    local pipe = io.popen(string.format(
        "convert '/tmp/wx_unread_col2.png' -crop 60x+15+0 +repage -colorspace gray -scale 1x%d! txt:- 2>/dev/null | grep -oP 'gray\\(\\K[0-9.]+'",
        wh))
    if not pipe then return nil, "row detection failed" end

    local states, prev_v, y = {}, 255, 0
    for line in pipe:lines() do
        local v = tonumber(line)
        if v then
            if v < 200 and prev_v >= 210 then
                table.insert(states, {type="start", y=y})
            elseif v >= 210 and prev_v < 200 then
                table.insert(states, {type="end", y=y})
            end
            prev_v = v; y = y + 1
        end
    end
    pipe:close()

    local rows = {}
    for i = 1, #states do
        if states[i].type == "start" and i < #states then
            local h = states[i+1].y - states[i].y
            if h >= 50 and h <= 80 then
                table.insert(rows, {y = states[i].y, h = h})
            end
        end
    end

    local result = {}
    for _, r in ipairs(rows) do
        if r.y > 80 then
            os.execute(string.format(
                "convert '/tmp/wx_unread_col2.png' +repage -crop 15x15+68+%d +repage '/tmp/wx_unread_badge.png' 2>/dev/null",
                r.y))
            local rp = io.popen(
                "convert /tmp/wx_unread_badge.png -fx '(r>0.78&&g<0.47&&b<0.47)?1:0' -format '%[fx:mean*100]' info: 2>/dev/null")
            if rp then
                local pct = tonumber(rp:read("*a"):match("[%d.]+")) or 0
                rp:close()
                if pct > 5 then
                    table.insert(result, {
                        x = wx + col1_w + 30,
                        y = wy + r.y + 35,
                        badge_x = wx + col1_w + 68 + 7,
                        badge_y = wy + r.y + 7,
                        row_y = r.y,
                        row_h = r.h,
                    })
                end
            end
        end
    end

    return result
end

function M.has_unread()
    local rows = M.detect_unread()
    return rows and #rows > 0
end

function M.unread_count()
    local rows = M.detect_unread()
    return rows and #rows or 0
end

function M.click_unread(index)
    local rows = M.detect_unread()
    if not rows or #rows == 0 then return M end
    local r = rows[index]
    if not r then return M end
    M.activate()
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", r.x, r.y))
    sleep(800000)
    return M
end

-- === OCR 语义定位 ===

function M.capture()
    return ocr.capture()
end

function M.capture_raw()
    return ocr.capture_raw()
end

function M.find_text(target)
    local data, err = ocr.capture_raw()
    if not data then return nil, err end
    for _, b in ipairs(data.boxes or {}) do
        if b.text == target then
            return {x = math.floor(b.x + b.w / 2), y = math.floor(b.y + b.h / 2), box = b}
        end
    end
    return nil, "not found: " .. target
end

function M.find_text_partial(partial)
    local data, err = ocr.capture_raw()
    if not data then return nil, err end
    for _, b in ipairs(data.boxes or {}) do
        if b.text:find(partial, 1, true) then
            return {x = math.floor(b.x + b.w / 2), y = math.floor(b.y + b.h / 2), box = b}
        end
    end
    return nil, "not found: " .. partial
end

function M.click_text(target)
    local pos, err = M.find_text(target)
    if not pos then return M end
    M.activate()
    sleep(200000)
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", pos.x, pos.y))
    sleep(500000)
    return M
end

function M.click_text_partial(partial)
    local pos, err = M.find_text_partial(partial)
    if not pos then return M end
    M.activate()
    sleep(200000)
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", pos.x, pos.y))
    sleep(500000)
    return M
end

-- === 监控 ===

function M.monitor(opts)
    opts = opts or {}
    if _record_enabled and opts.record ~= false then start_recording() end
    local ok, err = pcall(ocr.monitor, {
        interval_ms = opts.interval_ms or 3000,
        on_message = opts.on_message,
        on_initial = opts.on_initial,
        on_error = opts.on_error,
    })
    if _record_enabled then stop_recording() end
    if not ok then error(err) end
    return M
end

-- === 手动录屏 ===

function M.start_recording(output, duration)
    local out = output or "/tmp/wx_record.mp4"
    local cmd = string.format(
        "ffmpeg -y -f x11grab -r 10 -s 2560x1440 -i :0.0 "
        .. "-vcodec libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p "
        .. "-t %d '%s' & echo $!", duration or 15, out)
    local f = io.popen(cmd, "r")
    if f then
        local pid = f:read("*a"); f:close()
        _recording_pid = pid:match("%d+")
        sleep(1000000)
    end
    return M
end

function M.stop_recording()
    stop_recording()
    return M
end

-- === 校准 ===

function M.calibrate_icons()
    M.reload_icons()
    local cmd = string.format("cd '%s' && luajit tests/calibrate_icons.lua", dir)
    local ret = os.execute(cmd)
    M.reload_icons()
    if ret ~= 0 then return nil, "calibration failed" end
    return M
end

return M
