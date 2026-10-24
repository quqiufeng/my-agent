-- Chrome 浏览器控制（LuaJIT + libxdo）
-- 用法:
--   local chrome = require("wechat_ocr.chrome")
--   chrome.new_tab()
--   chrome.type("文字")       -- 粘贴中文
--   chrome.key("ctrl+v")     -- 按键
--   chrome.ai_search("问题")  -- AI模式搜索

package.path = "/opt/my-agent/wechat-ocr/lua/?.lua;" .. package.path
local ffi = require("ffi")
require("xdo_shim").install()
local Xdo = require("xdo")
local xd
ffi.cdef[[int usleep(unsigned int); int getpid(void);]]

local PID = ffi.C.getpid()
local TXT_TMP = string.format("/tmp/_chrome_txt_%d.txt", PID)

-- 获取 Chrome 窗口 ID
local function display()
    if not xd then xd = Xdo.new() end
    return xd
end

local function wid()
    local best, area = nil, 0
    for _, w in ipairs(display():find("Chrome")) do
        local g = w.geom
        if g and g.w * g.h > area then best, area = tonumber(w.id), g.w * g.h end
    end
    return best
end

-- 激活 Chrome 后发送按键（不要用 XSendEvent 直发后台窗口）
local function key(keys)
    local id = wid()
    if id then
        display():activate(id)
        display():raise(id)
        ffi.C.usleep(150000)
        display():key(0, keys)
        ffi.C.usleep(150000)
    end
end

local M = {}

-- 新标签
function M.new_tab()
    key("ctrl+t")
    ffi.C.usleep(300000)
end

-- 新标签打开指定网址
function M.open(url)
    M.new_tab()
    M.type(url)
    key("Return")
    ffi.C.usleep(300000)
end

-- 新标签 Google 搜索
function M.search(keyword)
    M.new_tab()
    M.type(keyword)
    key("Return")
    ffi.C.usleep(300000)
end

-- 粘贴文字（中文用剪贴板）
function M.type(text)
    local f = io.open(TXT_TMP, "w")
    if f then f:write(text); f:close() end
    os.execute("xclip -selection clipboard < " .. TXT_TMP .. " &>/dev/null &")
    ffi.C.usleep(100000)
    key("ctrl+v")
    ffi.C.usleep(200000)
end

-- 按键
function M.key(keys)
    key(keys)
end

-- AI 搜索：新标签 → 粘贴 → Tab → 回车
function M.ai_search(keyword)
    M.new_tab()
    M.type(keyword)
    key("Tab")
    ffi.C.usleep(50000)
    key("Return")
end

-- 截图
function M.screenshot(path)
    path = path or "/tmp/chrome_ss.png"
    local id = wid()
    if not id then return false end
    local gf = io.popen("xdotool getwindowgeometry " .. id .. " 2>/dev/null")
    local g = gf:read("*a"); gf:close()
    local wx = tonumber(g:match("Position: (%d+)"))
    local wy = tonumber(g:match(",(%d+)"))
    local ww = tonumber(g:match("Geometry: (%d+)"))
    local wh = tonumber(g:match("x(%d+)"))
    os.execute(string.format("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null", ww, wh, wx, wy, path))
    for i = 1, 20 do
        local f = io.open(path, "r")
        if f then local sz = f:seek("end"); f:close(); if sz > 1000 then break end end
        ffi.C.usleep(100000)
    end
    return path
end

return M
