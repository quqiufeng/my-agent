-- Chrome 浏览器控制（xdotool，跟操作微信一样）
-- 用法:
--   local chrome = require("wechat_ocr.chrome")
--   chrome.new_tab()
--   chrome.type("文字")       -- 粘贴中文
--   chrome.key("ctrl+v")     -- 按键
--   chrome.ai_search("问题")  -- AI模式搜索

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int); int getpid(void);]]

local PID = ffi.C.getpid()
local TXT_TMP = string.format("/tmp/_chrome_txt_%d.txt", PID)

-- 获取 Chrome 窗口 ID
local function wid()
    local f = io.popen("xdotool search --name Chrome 2>/dev/null")
    local ids = f:read("*a"); f:close()
    for id in ids:gmatch("%d+") do
        local gf = io.popen("xdotool getwindowgeometry " .. id .. " 2>/dev/null")
        local g = gf:read("*a"); gf:close()
        if g then
            local w = tonumber(g:match("Geometry: (%d+)"))
            if w and w > 500 then return tonumber(id) end
        end
    end
    return nil
end

-- 按键
local function key(keys)
    local id = wid()
    if id then os.execute("xdotool key --window " .. id .. " " .. keys .. " &>/dev/null &") end
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
