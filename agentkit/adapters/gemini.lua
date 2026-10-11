-- agentkit/adapters/gemini.lua — Google Gemini (gemini.google.com/app) 自动化
--   local g = ak.app("gemini")
--   g.new_chat(); g.ask("用一句话介绍你自己")
--   print(g.read_text())
local map = require("agentkit.map")
local x11 = require("agentkit.x11")
local M = {}

local m = map.load("gemini")
M.map = m

local function win() return m:window({ exact = false }) end
local function sleep(s) os.execute("sleep " .. tostring(s or 0.4)) end

-- 是否已在对话中（convo_area 有内容 → 输入框在底部）
local function in_conversation(w)
    local b = m:ocr("convo_area", w)
    return #b > 0
end

function M.window() return win() end

-- 新对话（清空上下文回到居中输入）
function M.new_chat()
    local w = win(); if not w then return false, "no window" end
    w:activate(); m:click("sidebar_new_chat", w); sleep(1.0)
    return true
end

-- 聚焦输入框（按状态选择居中/底部）
function M.focus_input(w)
    w = w or win()
    if in_conversation(w) then
        m:click("input_box_bottom", w)
    else
        m:click("input_box", w)
    end
    sleep(0.5)
    return w
end

-- 提问：聚焦 → 粘贴 → 回车 → 等待
-- opts = { wait=秒(默认8), type_wait=秒 }
function M.ask(prompt, opts)
    opts = opts or {}
    local w = win(); if not w then return false, "no window" end
    w:activate(); sleep(0.3)
    M.focus_input(w)
    x11.paste(prompt); sleep(opts.type_wait or 0.6)
    os.execute("xdotool key --clearmodifiers Return")
    sleep(opts.wait or 8)
    return true
end

-- 读取对话内容（按行排序）
function M.read()
    local w = win(); if not w then return {} end
    local b = m:ocr("convo_area", w)
    table.sort(b, function(a, c)
        if math.abs(a.gy - c.gy) > 8 then return a.gy < c.gy end
        return a.gx < c.gx
    end)
    local t = {}
    for _, o in ipairs(b) do t[#t + 1] = o.text end
    return t, b
end

function M.read_text()
    local t = M.read()
    return table.concat(t, "")
end

return M
