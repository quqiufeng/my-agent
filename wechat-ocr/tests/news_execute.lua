#!/usr/bin/env luajit
-- news_execute.lua — 文件传输助手新消息 → 读取 → 回复
-- 检测未读 → 点进去 → 读最新消息 → 回复"收到！马上处理"+引用原文

local ffi = require("ffi")
local cjson = require("cjson")
ffi.cdef[[int usleep(unsigned int);]]
local badge = require("wechat_ocr.badge_detect")

-- 点击条目
local function click_entry(entry, win)
    local cx = win.x + entry.rx + entry.w / 2
    local cy = win.y + entry.ry + entry.h / 2
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", cx, cy))
    ffi.C.usleep(1500000)
end

-- 读取最新一条消息（Ctrl+A → Ctrl+C 复制消息区域）
local function read_latest_message(win)
    -- 点击消息区域激活，然后全选复制
    local click_x = win.x + math.floor(win.w * 0.70)
    local click_y = win.y + win.h - 250
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", click_x, click_y))
    ffi.C.usleep(300000)

    -- Ctrl+A 全选 → Ctrl+C 复制
    os.execute("xdotool key ctrl+a 2>/dev/null")
    ffi.C.usleep(200000)
    os.execute("xdotool key ctrl+c 2>/dev/null")
    ffi.C.usleep(500000)

    -- 读剪贴板
    local pipe = io.popen("xclip -selection clipboard -o 2>/dev/null")
    if not pipe then return "" end
    local text = pipe:read("*a"); pipe:close()
    
    -- 取最后一段非空文本（最新消息）
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        if #line > 1 then table.insert(lines, line) end
    end
    return #lines > 0 and lines[#lines] or text:sub(1, 200)
end

-- 回复（粘贴+发送）
local function reply(content)
    local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
    local wx = tonumber(geo:match("Position: (%d+)"))
    local wy = tonumber(geo:match(",(%d+)"))
    local ww = tonumber(geo:match("Geometry: (%d+)"))
    local wh = tonumber(geo:match("x(%d+)"))

    -- 点输入框
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + ww - 200, wy + wh - 80))
    ffi.C.usleep(500000)

    -- 剪贴板写入
    local f = io.open("/tmp/_ft_reply.txt", "w")
    if f then f:write(content); f:close() end
    os.execute("xclip -selection clipboard < /tmp/_ft_reply.txt 2>/dev/null")
    ffi.C.usleep(200000)
    os.execute("xdotool key ctrl+v 2>/dev/null")
    ffi.C.usleep(300000)
    os.execute("xdotool key Return 2>/dev/null")
end

-- ===== 主流程 =====
io.write("检测中...\n"); io.flush()

local result = badge.detect()
if not result then io.write("检测失败\n"); os.exit(1) end

local ft_entry = badge.find_file_transfer(result)
if not ft_entry then io.write("未找到文件传输助手\n"); os.exit(0) end

if not ft_entry.found then
    io.write("文件传输助手无未读消息\n")
    os.exit(0)
end

io.write("有未读消息，打开...\n"); io.flush()
click_entry(ft_entry, result.win)

-- 滚到底部看最新消息
os.execute("xdotool key End 2>/dev/null")
ffi.C.usleep(1000000)

io.write("读取最新消息...\n"); io.flush()
local msg = read_latest_message(result.win)
if #msg == 0 then io.write("未能读取消息\n"); os.exit(1) end

io.write("最新消息:\n" .. msg:sub(1, 300) .. "\n\n"); io.flush()

-- 构造回复
local reply_text = "收到！马上处理\n\n—— 原文：\n" .. msg:sub(1, 200)

io.write("回复中...\n"); io.flush()
reply(reply_text)

io.write("已完成\n")
