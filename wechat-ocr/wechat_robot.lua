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

local ocr = require("wechat_ocr")
local dir = "/opt/my-agent/wechat-ocr"

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
