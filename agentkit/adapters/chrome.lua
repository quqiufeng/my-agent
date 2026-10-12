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
    require("agentkit.x11").ime_restore()                  -- 还原用户输入法
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

-- ── 与 chrome-devtools MCP 结合：授权用视觉点开 ──────────────────
-- 「配置允许」= chrome://inspect/#remote-debugging 里的
--   ☑ Allow remote debugging for this browser instance
-- 开启后 Chrome 会 `Server running at 127.0.0.1:9222`，MCP(--autoConnect) 才能连。
-- 用端口 9222 判断状态（比 OCR 稳），未开则用视觉点复选框。

local function port_open(p)
    p = p or 9222
    local out = require("agentkit.x11").sh(("ss -ltn 2>/dev/null | grep ':%d '"):format(p))
    return out ~= ""
end
M.port_open = port_open

-- 确保「允许远程调试」已开启；已开则不动。返回 ok, 说明
function M.enable_remote_debugging()
    local w = win(); if not w then return false, "no window" end
    if port_open(9222) then return true, "already on" end
    w:activate(); sleep(0.3)
    M.goto("chrome://inspect/#remote-debugging"); sleep(1.6)
    -- 复选框在标签左侧；OCR 找标签再点其左边
    for _, o in ipairs(w:ocr_bands({ 180, 180, 1700, 320 }, 150)) do
        if o.text:find("Allow remote debugging") or o.text:find("remote debugging")
            or o.text:find("允许") or o.text:find("远程调试") then
            w:click(math.floor(o.gx - 16), math.floor(o.gy + 6)); sleep(1.2)
            break
        end
    end
    if port_open(9222) then return true, "enabled" end
    return false, "clicked but 9222 not open"
end

-- 每次连接的“同意”：扫描并点击授权按钮（信息栏/气泡在工具栏下方）
local CONSENT_WORDS = { "允许", "同意", "接受", "继续", "启用", "开启",
                        "Allow", "Accept", "Connect", "Continue", "OK", "确定" }

-- opts = { window=, texts=, region={x,y,w,h} }，返回 ok, 命中文案
function M.accept_consent(opts)
    opts = opts or {}
    local w = opts.window or win(); if not w then return false, "no window" end
    local words = opts.texts or CONSENT_WORDS
    -- 默认先扫“工具栏下方”的弹条区；找不到再扫上半屏
    local regions = { opts.region or { 0, 80, w.w, 180 }, { 0, 80, w.w, math.min(w.h - 80, 700) } }
    for _, rg in ipairs(regions) do
        local boxes = w:ocr_bands(rg, 160)
        for _, word in ipairs(words) do
            for _, o in ipairs(boxes) do
                if o.text:find(word, 1, true) then
                    w:click(math.floor(o.gx + o.w / 2), math.floor(o.gy + o.h / 2))
                    return true, o.text
                end
            end
        end
    end
    return false, "no consent button"
end

-- 后台守望：在 seconds 秒内轮询，出现同意按钮即点掉（供 MCP 连接期间使用）
function M.watch_consent(seconds, opts)
    seconds = seconds or 30
    local t = 0
    while t < seconds do
        if M.accept_consent(opts) then return true end
        os.execute("sleep 1"); t = t + 1
    end
    return false
end

return M
