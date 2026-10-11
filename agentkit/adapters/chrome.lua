-- agentkit/adapters/chrome.lua — Chrome 自动化 API（基于 maps/chrome.lua）
--   local ch = ak.app("chrome")
--   ch.goto("example.com"); print(ch.title()); for _,l in ipairs(ch.read()) do ... end
local map = require("agentkit.map")
local M = {}

local m = map.load("chrome")
M.map = m

local function sleep(s) os.execute("sleep " .. tostring(s or 0.3)) end
local function xdo(c) os.execute("export DISPLAY=${DISPLAY:-:0}; " .. c) end
local function win() return m:window({ exact = false }) end

function M.window() return win() end
function M.click(name) local w = win(); return w and m:click(name, w) end

-- 地址栏导航
function M.goto(url)
    local w = win(); if not w then return false, "no window" end
    w:activate(); sleep(0.3)
    m:click("omnibox", w); sleep(0.4)
    xdo("xdotool key --clearmodifiers ctrl+a"); sleep(0.2)
    require("agentkit.x11").ime_en(); sleep(0.15)          -- URL 用英文输入法
    xdo(("xdotool type --delay 20 %q"):format(url)); sleep(0.5)
    xdo("xdotool key --clearmodifiers Return"); sleep(1.2)
    return true
end

-- 新标签页（可选直接导航）
function M.new_tab(url)
    local w = win(); if not w then return false, "no window" end
    m:click("new_tab", w); sleep(0.6)
    if url then return M.goto(url) end
    return true
end

function M.reload()  local w = win(); return w and m:click("reload", w) end
function M.back()    local w = win(); return w and m:click("back", w) end
function M.forward() local w = win(); return w and m:click("forward", w) end
function M.home()    local w = win(); return w and m:click("home", w) end

-- 读取当前标签页文本（页面区 OCR，按行排序）
function M.read()
    local w = win(); if not w then return {} end
    local boxes = m:ocr("page", w)
    table.sort(boxes, function(a, b)
        if math.abs(a.gy - b.gy) > 8 then return a.gy < b.gy end
        return a.gx < b.gx
    end)
    local lines = {}
    for _, b in ipairs(boxes) do lines[#lines + 1] = b.text end
    return lines, boxes
end

-- 当前活动标签标题（取自窗口标题，稳定）
function M.title()
    local w = win(); if not w then return nil end
    local name = require("agentkit.x11").win_name(w.id)
    return (name:gsub("%s*%-%s*Google Chrome%s*$", ""))
end

return M
