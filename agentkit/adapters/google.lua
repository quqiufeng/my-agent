-- agentkit/adapters/google.lua — Google 搜索自动化（google.com）
--   local g = ak.app("google")
--   g.search("DeepSeek"); for _,l in ipairs(g.read_results()) do print(l) end
--   g.scroll_bottom(); g.next_page()
local map = require("agentkit.map")
local x11 = require("agentkit.x11")
local ocr = require("agentkit.ocr")
local M = {}

local m = map.load("google")
M.map = m

local function win() return m:window({ exact = false }) end
local function sleep(s) os.execute("sleep " .. tostring(s or 0.4)) end

-- 分区 OCR：大页面必须分带识别，否则小字丢失
local function ocr_bands(w, x, y, ww, hh, band, sc)
    sc = sc or 1.5
    local out, yy = {}, y
    while yy < y + hh do
        local bh = math.min(band, y + hh - yy)
        local t = "/tmp/opencode/_gband.png"
        w:capture_region(x, yy, ww, bh, t)
        os.execute(("convert %s -resize %d%% %s"):format(t, math.floor(sc * 100), "/tmp/opencode/_gband2.png"))
        for _, o in ipairs(ocr.run("/tmp/opencode/_gband2.png")) do
            out[#out + 1] = { x = x + o.x / sc, y = yy + o.y / sc, text = o.text }
        end
        yy = yy + band
    end
    table.sort(out, function(a, b)
        if math.abs(a.y - b.y) > 8 then return a.y < b.y end
        return a.x < b.x
    end)
    local lines = {}
    for _, o in ipairs(out) do lines[#lines + 1] = o.text end
    return lines, out
end

function M.window() return win() end

-- 搜索：结果页用顶部框，否则首页框
function M.search(q, opts)
    opts = opts or {}
    local w = win(); if not w then return false, "no window" end
    w:activate(); sleep(0.3)
    local title = x11.win_name(w.id)
    if title:find("搜索") then m:click("search_box_top", w) else m:click("search_box_home", w) end
    sleep(0.5)
    os.execute("xdotool key --clearmodifiers ctrl+a"); sleep(0.1)
    x11.paste(q); sleep(0.5)
    os.execute("xdotool key --clearmodifiers Return"); sleep(opts.wait or 3)
    return true
end

-- 读取当前视口结果列
function M.read_results()
    local w = win(); if not w then return {} end
    return ocr_bands(w, 330, 330, 1130, 1050, 250, 1.5)
end

-- 滚到底部
function M.scroll_bottom(w)
    w = w or win(); if not w then return false end
    w:activate(); sleep(0.2)
    os.execute("xdotool key --clearmodifiers End")
    for _ = 1, 10 do
        os.execute("xdotool key --clearmodifiers Page_Down"); sleep(0.25)
    end
    return true
end

-- 翻页（点击底部“下一页”）
function M.next_page()
    local w = win(); if not w then return false end
    local ok = w:click_text("下一页", { 600, 1240, 1000, 130 }, { retries = 3 })
    if not ok then return false end
    sleep(2.5)
    return true
end

return M
