-- WeChat Robot Library
-- 基于已验证测试脚本重构，使用坐标缓存 + 窗口左上角动态计算
-- 用法: local robot = require("wechat_robot")
--
-- 流式调用示例:
--   robot:search("小王"):send("你好"):send_file("a.mp4"):screenshot()

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]
ffi.cdef[[int getpid(void);]]
ffi.cdef[[
    int         joycaption_init(const char* model, const char* mmproj, int use_gpu);
    const char* joycaption_analyze(const char* image, const char* prompt);
    void        joycaption_free();
]]

local dir = "/opt/my-agent/wechat-ocr"

-- 优先加载仓库内的模块与动态库，保证运行版本与源码一致
package.path = dir .. "/lua/?.lua;" .. dir .. "/lua/?/init.lua;" .. (package.path or "")
package.cpath = dir .. "/lib/?.so;" .. (package.cpath or "")

local ocr = require("wechat_ocr")
local cjson = require("cjson")

local M = {}

-- === 状态 ===
local _recording_pid = nil
local _record_enabled = false
local _record_output = "/tmp/wx_robot_record.mp4"
local _icon_cache = nil

-- === 常量 ===
local HOME = os.getenv("HOME") or "/tmp"
local PID = ffi.C.getpid()
-- 用户级缓存优先，仓库内附带的旧缓存只作兜底，避免校准结果被覆盖
local ICON_CACHE_PATHS = {
    HOME .. "/.wechat_icons.json",
    dir .. "/wechat_icons.json",
}

-- 屏幕尺寸（惰性获取一次）
local SCREEN_W, SCREEN_H = 2560, 1440
local function screen_size()
    local f = io.popen("xdotool getdisplaygeometry 2>/dev/null")
    if f then
        local out = f:read("*a"); f:close()
        local w, h = out:match("(%d+)%s+(%d+)")
        if w and h then SCREEN_W, SCREEN_H = tonumber(w), tonumber(h) end
    end
    return SCREEN_W, SCREEN_H
end

-- 当前进程专属临时文件，避免并发/残留互相覆盖
local function tmp(name)
    return string.format("/tmp/wx_robot_%d_%s", PID, name)
end

local SIDEBAR_INDEX_MAP = {
    [1] = "WeChat",
    [2] = "Contacts",
    [3] = "Favorites",
    [4] = "Moments",
    [5] = "Channels",
    [6] = "Search",
    [7] = "MiniProgram",
}

local VLM_MODEL  = "/data/models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"
local VLM_MMPROJ = "/data/models/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf"
local _vlm_lib = nil

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

local function find_wechat_window()
    local pipe = io.popen("xdotool search --name 微信 2>/dev/null")
    if not pipe then return nil end
    local ids = {}
    for line in pipe:lines() do
        local id = tonumber(line)
        if id then table.insert(ids, id) end
    end
    pipe:close()

    local best_id, best_area = nil, 0
    for _, id in ipairs(ids) do
        local gpipe = io.popen("xdotool getwindowgeometry " .. id .. " 2>/dev/null")
        if gpipe then
            local geo = gpipe:read("*a"); gpipe:close()
            local w = tonumber(geo:match("Geometry: (%d+)"))
            local h = tonumber(geo:match("x(%d+)"))
            if w and h then
                local area = w * h
                if area > best_area then
                    best_area = area
                    best_id = id
                end
            end
        end
    end
    return best_id
end

-- 确保微信窗口最大化（默认应最大化；若不是则用 wmctrl 最大化）
function M.ensure_maximized()
    local sw, sh
    do
        local f = io.popen("xdotool getdisplaygeometry 2>/dev/null")
        if f then local o = f:read("*a"); f:close(); sw, sh = o:match("(%d+)%s+(%d+)") end
    end
    local wid = find_wechat_window()
    if not wid then return M end
    local w, h
    do
        local f = io.popen("xdotool getwindowgeometry " .. wid .. " 2>/dev/null")
        if f then
            local o = f:read("*a"); f:close()
            w = tonumber(o:match("Geometry: (%d+)"))
            h = tonumber(o:match("x(%d+)"))
        end
    end
    -- 明显小于屏幕 → 视为未最大化
    if sw and w and h and (w < tonumber(sw) - 40 or h < tonumber(sh) - 80) then
        os.execute(string.format("wmctrl -i -r 0x%x -b add,maximized_vert,maximized_horz 2>/dev/null", wid))
        sleep(800000)
    end
    return M
end

local _last_activate = 0

-- force=true 时强制执行；否则 2 秒内重复调用只执行一次，避免一次操作里多次激活叠加等待
function M.activate(force)
    local now = os.time()
    if not force and now - _last_activate < 2 then return M end
    _last_activate = now

    local wid = find_wechat_window()
    if wid then
        -- 先取消最小化再激活，确保微信真正到前台
        os.execute("xdotool windowmap " .. wid .. " 2>/dev/null")
        os.execute("xdotool windowraise " .. wid .. " 2>/dev/null")
        os.execute("xdotool windowfocus " .. wid .. " 2>/dev/null")
        os.execute("xdotool windowactivate " .. wid .. " 2>/dev/null")
    end
    M.ensure_maximized()   -- 自动化前先确保窗口最大化
    sleep(800000)
    -- 点一下标题栏确保真正获取焦点
    local win = M.get_window_rect()
    if win then
        os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", win.x + 100, win.y + 20))
        sleep(300000)
    end
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

-- === VLM 加载 ===

local function vlm_load()
    if _vlm_lib then return _vlm_lib end
    local paths = {
        "libjoycaption",
        "/opt/my-agent/joycaption-wrapper/libjoycaption.so",
        os.getenv("HOME") .. "/my-agent/joycaption-wrapper/libjoycaption.so",
    }
    for _, p in ipairs(paths) do
        local ok, lib = pcall(ffi.load, p)
        if ok then
            local ret = lib.joycaption_init(VLM_MODEL, VLM_MMPROJ, 1)
            if ret == 0 then
                _vlm_lib = lib
                return lib
            end
        end
    end
    return nil
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
            -- activate 内部有 2 秒去重，重复调用不会叠加等待
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
    M.activate()
    local pos, err = M.get_icon_pos(name, area)
    if not pos then
        io.stderr:write("[wechat_robot] click_icon failed: " .. tostring(err) .. "\n")
        return nil, err
    end
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", pos.x, pos.y))
    sleep(500000)
    return M
end

-- 兼容文档命名：按名称点击图标
function M.click_icon_rel(name, area)
    return M.click_icon(name, area)
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
    local sw, sh = screen_size()
    local cmd = string.format(
        "ffmpeg -y -f x11grab -r 10 -s %dx%d -i :0.0 "
        .. "-vcodec libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p "
        .. "'%s' & echo $!", sw, sh, _record_output)
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
    if not ok then
        io.stderr:write("[wechat_robot] init failed: " .. tostring(err) .. "\n")
        return nil, err
    end
    if _record_enabled then start_recording() end
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
    -- 用 wechat_ocr 模块的稳健发送：点输入框 + 剪贴板粘贴 + 回车
    local ok, err = ocr.send(text)
    if not ok then
        io.stderr:write("[wechat_robot] send failed: " .. tostring(err) .. "\n")
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

    local sw, sh = screen_size()

    -- 框选全屏
    os.execute("xdotool mousemove 0 0 2>/dev/null")
    sleep(100000)
    os.execute("xdotool mousedown 1 2>/dev/null")
    sleep(100000)
    os.execute(string.format("xdotool mousemove %d %d 2>/dev/null", sw, sh))
    sleep(300000)
    os.execute("xdotool mouseup 1 2>/dev/null")
    sleep(500000)

    -- 双击确认（屏幕中心）
    os.execute(string.format("xdotool mousemove %d %d 2>/dev/null", math.floor(sw / 2), math.floor(sh / 2)))
    sleep(200000)
    os.execute("xdotool click --repeat 2 --delay 150 1 2>/dev/null")
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

-- 第二列（聊天列表）几何参数：以 2560 宽窗口为基准，按窗口宽度等比缩放
local function col_geometry(win)
    local scale = (win.w or 2560) / 2560
    return {
        col1_w = math.max(40, math.floor(75 * scale)),
        col2_w = math.max(120, math.floor(445 * scale)),
    }
end

-- 截图微信窗口并裁出第二列，返回 { full=..., col2=... }
local function capture_col2(win)
    local full = tmp("unread_full.png")
    local col2 = tmp("unread_col2.png")
    local col1_w = col_geometry(win).col1_w
    local col2_w = col_geometry(win).col2_w
    os.execute(string.format(
        "import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null",
        win.w, win.h, win.x, win.y, full))
    os.execute(string.format(
        "convert '%s' +repage -crop %dx%d+%d+0 +repage '%s' 2>/dev/null",
        full, col2_w, win.h, col1_w, col2))
    return full, col2
end

-- VLM 识别第二列未读消息（红底白字数字徽章）
-- 返回每个未读项的坐标：{ x, y, badge_x, badge_y, row, count, name }
function M.detect_unread_vlm(debug)
    M.activate()
    M.click_sidebar(1)  -- 先点击微信图标，确保聊天列表显示
    local win = M.get_window_rect()
    if not win then return nil, "no window" end

    local wx, wy, wh = win.x, win.y, win.h
    local geom = col_geometry(win)
    local col1_w, col2_w = geom.col1_w, geom.col2_w
    local scale = (win.w or 2560) / 2560

    local _full, col2_path = capture_col2(win)

    local lib = vlm_load()
    if not lib then return nil, "vlm not available" end

    if debug then
        flush("[detect_unread_vlm] VLM analyzing...\n")
    end

    local prompt = [[Look at this WeChat chat list (second column).
Find all contacts that have unread messages, shown as a red circular badge with a white number on the top-right corner of the avatar.
For each unread contact, list:
- Row number counting from the first contact in the visible list (starting from 1)
- The unread number shown in the red badge
- The contact name if readable

Format exactly: "1. 小王: 3"
If no unread badges, reply only "None".]]

    local result_ptr = lib.joycaption_analyze(col2_path, prompt)
    if result_ptr == ffi.NULL then return nil, "vlm returned null" end
    local text = ffi.string(result_ptr)

    if debug then
        flush(string.format("[detect_unread_vlm] VLM output:\n%s\n", text))
    end

    local chat_list_start = math.floor(110 * scale)
    local row_height = math.max(1, math.floor(70 * scale))
    local result = {}
    for line in text:gmatch("[^\n]+") do
        local row_str, name, count = line:match("^(%d+)%.%s*([^:]+)%s*:%s*(%d+)")
        if row_str then
            local row = tonumber(row_str)
            if row and row > 0 then
                local y = wy + chat_list_start + (row - 1) * row_height + row_height / 2
                table.insert(result, {
                    x = wx + col1_w + 30,
                    y = y,
                    badge_x = wx + col1_w + 350,
                    badge_y = y - 15,
                    row = row,
                    count = tonumber(count) or 0,
                    name = name and name:gsub("^%s*", ""):gsub("%s*$", "") or "",
                })
            end
        end
    end

    return result
end

-- 基于红色徽章直接检测未读（不依赖行识别，对 VLM 失败的场景更鲁棒）
function M.detect_unread_red(debug)
    M.activate()
    M.click_sidebar(1)  -- 先点击微信图标，确保聊天列表显示
    local win = M.get_window_rect()
    if not win then return nil, "no window" end

    local wx, wy, wh = win.x, win.y, win.h
    local geom = col_geometry(win)
    local col1_w, col2_w = geom.col1_w, geom.col2_w

    local _full, col2_path = capture_col2(win)

    if debug then
        os.execute(string.format("cp '%s' '%s/wx_unread_debug_col2.png' 2>/dev/null", col2_path, HOME))
    end

    local cmd = string.format(
        "convert '%s' -fx '(r>0.78&&g<0.47&&b<0.47)?1:0' " ..
        "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1 " ..
        "| grep -v 'bgcolor\\|id:\\|0:.*gray'", col2_path)
    local pipe = io.popen(cmd)
    if not pipe then return nil, "red detection failed" end

    local candidates = {}
    for line in pipe:lines() do
        local id, w, h, x, y, area = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
        if w and h and x and y and area then
            local wn, hn, an = tonumber(w), tonumber(h), tonumber(area)
            local ratio = math.max(wn / hn, hn / wn)
            if an >= 10 and an <= 300 and wn >= 5 and hn >= 5 and ratio <= 3 then
                table.insert(candidates, {
                    x = tonumber(x), y = tonumber(y), w = wn, h = hn, area = an,
                })
            end
        end
    end
    pipe:close()

    if debug then
        flush(string.format("[detect_unread_red] red candidates: %d\n", #candidates))
    end

    -- 合并邻近候选：红底白字会把同一个徽章分成多个红色组件
    local groups = {}
    for _, c in ipairs(candidates) do
        local cx = c.x + c.w / 2
        local cy = c.y + c.h / 2
        local merged = false
        for _, g in ipairs(groups) do
            local dx = cx - g.cx
            local dy = cy - g.cy
            if dx*dx + dy*dy < 900 then  -- 30px 半径内合并
                g.cx = (g.cx * g.n + cx) / (g.n + 1)
                g.cy = (g.cy * g.n + cy) / (g.n + 1)
                g.area = g.area + c.area
                g.n = g.n + 1
                merged = true
                break
            end
        end
        if not merged then
            table.insert(groups, {cx = cx, cy = cy, area = c.area, n = 1})
        end
    end

    if debug then
        flush(string.format("[detect_unread_red] merged groups: %d\n", #groups))
    end

    -- 按 x 偏右程度过滤：未读徽章在 col2 右侧（头像右上角）
    local result = {}
    for _, g in ipairs(groups) do
        if g.cx > col2_w * 0.55 then
            local badge_cx = wx + col1_w + math.floor(g.cx)
            local badge_cy = wy + math.floor(g.cy)
            table.insert(result, {
                x = wx + col1_w + 100,        -- 点击行中部
                y = badge_cy,                 -- 行中心约等于徽章高度
                badge_x = badge_cx,
                badge_y = badge_cy,
                area = g.area,
                parts = g.n,
            })
        end
    end

    table.sort(result, function(a, b) return a.y < b.y end)

    if debug then
        for i, r in ipairs(result) do
            flush(string.format("  %d. badge (%d,%d) area=%d\n", i, r.badge_x, r.badge_y, r.area))
        end
    end

    return result
end

-- 优先使用红色检测，未检测到再尝试 VLM
function M.detect_unread(debug)
    local rows = M.detect_unread_red(debug)
    if rows and #rows > 0 then return rows end
    return M.detect_unread_vlm(debug)
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

function M.debug_unread()
    return M.detect_unread(true)
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
    local win = data.win or {}
    local wx, wy = win.x or 0, win.y or 0
    for _, b in ipairs(data.boxes or {}) do
        if b.text == target then
            return {x = math.floor(wx + b.x + b.w / 2), y = math.floor(wy + b.y + b.h / 2), box = b}
        end
    end
    return nil, "not found: " .. target
end

function M.find_text_partial(partial)
    local data, err = ocr.capture_raw()
    if not data then return nil, err end
    local win = data.win or {}
    local wx, wy = win.x or 0, win.y or 0
    for _, b in ipairs(data.boxes or {}) do
        if b.text:find(partial, 1, true) then
            return {x = math.floor(wx + b.x + b.w / 2), y = math.floor(wy + b.y + b.h / 2), box = b}
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
    local sw, sh = screen_size()
    local cmd = string.format(
        "ffmpeg -y -f x11grab -r 10 -s %dx%d -i :0.0 "
        .. "-vcodec libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p "
        .. "-t %d '%s' & echo $!", sw, sh, duration or 15, out)
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
    local cmd = string.format("cd '%s' && luajit tests/calibrate_icons.lua", dir)
    local ret = os.execute(cmd)
    M.reload_icons()
    if ret ~= 0 then return nil, "calibration failed" end
    return M
end

function M.clear_calibration()
    _icon_cache = nil
    for _, path in ipairs(ICON_CACHE_PATHS) do
        os.remove(path)
    end
    return M
end

return M
