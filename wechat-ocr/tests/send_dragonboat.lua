#!/usr/bin/env luajit
-- 搜索张雪娇 → 发送端午节快乐 → 全程录像 → 录像发送到文件传输助手

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]

local function log(msg)
    io.write("[" .. os.date("%H:%M:%S") .. "] " .. msg .. "\n"); io.flush()
end

-- 获取微信窗口位置
local function get_wx_win()
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    ffi.C.usleep(500000)
    local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
    local wx = tonumber(geo:match("Position: (%d+)"))
    local wy = tonumber(geo:match(",(%d+)"))
    local ww = tonumber(geo:match("Geometry: (%d+)"))
    local wh = tonumber(geo:match("x(%d+)"))
    return wx, wy, ww, wh
end

local HOME = os.getenv("HOME") or "/home/quqiufeng"

-- ===== 1. 开始录像 =====
local video_path = HOME .. "/端午节祝福.mp4"
log("开始录像: " .. video_path)
os.execute(string.format("ffmpeg -f x11grab -s 2560x1440 -i :0.0 -t 30 -pix_fmt yuv420p '%s' -y &>/dev/null &", video_path))
ffi.C.usleep(500000)

-- ===== 2. 搜索张雪娇 =====
log("搜索张雪娇...")
local wx, wy, ww, wh = get_wx_win()

-- 点搜索框
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + 180, wy + 50))
ffi.C.usleep(500000)

-- 输入
local f = io.open("/tmp/_zsj.txt", "w"); f:write("张雪娇"); f:close()
os.execute("xclip -selection clipboard < /tmp/_zsj.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(500000)

-- 回车搜索
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)

-- ===== 3. 点第一个结果 =====
log("点击张雪娇...")
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + 155, wy + 200))
ffi.C.usleep(1500000)

-- ===== 4. 输入并发送端午节快乐 =====
log("发送: 端午节快乐")
-- 点输入框
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + ww - 200, wy + wh - 80))
ffi.C.usleep(500000)

-- 粘贴内容
local f2 = io.open("/tmp/_dwk.txt", "w"); f2:write("端午节快乐"); f2:close()
os.execute("xclip -selection clipboard < /tmp/_dwk.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(500000)

-- 发送
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(2000000)

-- ===== 5. 停止录像 =====
log("停止录像...")
os.execute("pkill -f 'ffmpeg.*端午节祝福' 2>/dev/null")
ffi.C.usleep(1000000)

log("录像已保存: " .. video_path)

-- ===== 6. 发送录像到文件传输助手 =====
log("发送录像到文件传输助手...")

-- 搜索文件传输助手
wx, wy, ww, wh = get_wx_win()
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + 180, wy + 50))
ffi.C.usleep(500000)
local f3 = io.open("/tmp/_ft2.txt", "w"); f3:write("文件传输助手"); f3:close()
os.execute("xclip -selection clipboard < /tmp/_ft2.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(500000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)

-- 点文件发送图标
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + ww - 150, wy + wh - 80))
ffi.C.usleep(1000000)

-- 粘贴文件路径
local f4 = io.open("/tmp/_fv.txt", "w"); f4:write(video_path); f4:close()
os.execute("xclip -selection clipboard < /tmp/_fv.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(500000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(2000000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)

log("完成！")
