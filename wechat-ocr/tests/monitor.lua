#!/usr/bin/env luajit
-- WeChat 消息监控守护进程
-- 每 5 分钟检测第二列是否有红点（未读消息）
-- 用法: luajit monitor.lua &          # 后台运行
--       luajit monitor.lua --once     # 只检测一次

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]

----------------------------------------
-- 配置
----------------------------------------
local CHECK_INTERVAL = 300  -- 5 分钟（秒）
local SCREENSHOT_DIR = "/tmp/wechat_monitor"

-- 颜色输出
local RED = "\27[31m"
local GREEN = "\27[32m"
local RESET = "\27[0m"

----------------------------------------
-- 检测红点（用连通分量分析）
----------------------------------------
local function check_red_dots()
    -- 截图微信窗口
    os.execute("mkdir -p " .. SCREENSHOT_DIR)
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    ffi.C.usleep(500000)

    local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
    local win_x = tonumber(geo:match("Position: (%d+)"))
    local win_y = tonumber(geo:match(",(%d+)"))
    local win_w = tonumber(geo:match("Geometry: (%d+)"))
    local win_h = tonumber(geo:match("x(%d+)"))
    if not win_w then return -1, "无法获取微信窗口" end

    local shot = SCREENSHOT_DIR .. "/wechat.png"
    os.execute(string.format("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null", win_w, win_h, win_x, win_y, shot))

    -- 用 ImageMagick 分析红色区域
    -- R > G*2.2, R > B*2.2, R > 0.7, G < 0.5
    os.execute(string.format(
        "convert '%s' +repage -fx '(r>g*2.2&&r>b*2.2&&r>0.7&&g<0.5)?1:0' '/tmp/_mon_red.png' 2>/dev/null", shot))

    -- 连通分量分析
    local pipe = io.popen(string.format(
        "convert '/tmp/_mon_red.png' -define connected-components:verbose=true -connected-components 4 /dev/null 2>/dev/null | grep -v '0:\\|bgcolor\\|id:'"))
    local output = pipe:read("*a"); pipe:close()

    local count = 0
    for line in output:gmatch("[^\n]+") do
        local id, w, h, x, y, px = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
        if w and x and y and px then
            local nw, nh, nx, ny, np = tonumber(w), tonumber(h), tonumber(x), tonumber(y), tonumber(px)
            if nw >= 5 and nh >= 5 and nw <= 20 and nh <= 20 and nx < win_w * 0.4 and np >= 20 then
                count = count + 1
            end
        end
    end
    return count, nil
end

----------------------------------------
-- 主循环
----------------------------------------
local once = (arg and arg[1] == "--once")

io.write(string.format("%s [微信监控] 启动%s\n", os.date("%H:%M:%S"), once and "（单次模式）" or "（每5分钟检测）"))
io.flush()

local prev_count = 0

while true do
    local ok, msg = pcall(check_red_dots)
    if ok then
        local count = msg
        local ts = os.date("%H:%M:%S")
        if count > 0 then
            io.write(string.format("%s %s[%d 条未读]%s\n", ts, RED, count, RESET))
            if count ~= prev_count then
                prev_count = count
                -- 可以在这里添加通知逻辑，如播放声音、发消息等
            end
        else
            io.write(string.format("%s %s[无新消息]%s\n", ts, GREEN, RESET))
            prev_count = 0
        end
    else
        io.write(string.format("%s [错误] %s\n", os.date("%H:%M:%S"), tostring(msg)))
    end
    io.flush()

    if once then break end
    -- 等待间隔（每 10 秒检查一次是否到时间）
    for i = 1, CHECK_INTERVAL do
        ffi.C.usleep(1000000)
        -- 可以在这里添加信号处理
    end
end

io.write("监控结束\n")
