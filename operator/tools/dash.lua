-- operator/tools/dash.lua — 行情大屏渲染（白底·多面板，ImageMagick 矢量绘制）
-- 用法: luajit dash.lua <out.png> <data.tsv> [W] [H] [title]
-- data.tsv 行格式（TAB 分隔）:
--   IDX 名称 现价 涨跌 涨跌幅 今开 最高 最低
--   WL  名称 现价 涨跌 涨跌幅
--   K   名称 收盘1,收盘2,...
local out   = arg[1] or "/tmp/myagent_dash.png"
local dataf = arg[2] or "/tmp/myagent_dash.tsv"
local W     = tonumber(arg[3]) or 1600
local H     = tonumber(arg[4]) or 1000
local title = arg[5] or "行情大屏"

local FZH = "/opt/WordCard/LXGWWenKai-Regular.ttf"
local FEN = "/opt/WordCard/JetBrainsMono-Bold.ttf"
local BG, PANEL, GRID = "#ffffff", "#f4f6fa", "#e3e8ef"
local TXT, GRAY = "#1c2430", "#7a8699"
local UP, DOWN, FLAT = "#d0021b", "#0a9f4a", "#7a8699"

local cmd = { "convert", "-size", W .. "x" .. H, "xc:'" .. BG .. "'" }
local function qt(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function add(...) for _, v in ipairs({ ... }) do cmd[#cmd + 1] = v end end
local function rect(x1, y1, x2, y2, fill)
    add("-fill", qt(fill), "-stroke", "none", "-draw", qt(("rectangle %d,%d %d,%d"):format(x1, y1, x2, y2)))
end
local function text(x, y, s, size, col, font, grav)
    if grav then add("-gravity", grav) end
    add("-font", font or FZH, "-pointsize", tostring(size), "-fill", qt(col), "-annotate", "+" .. x .. "+" .. y, qt(s))
    if grav then add("-gravity", "NorthWest") end
end
local function cnum(v) if v >= 0 then return ("+%.2f"):format(v) else return ("%.2f"):format(v) end end
local function ccol(chg) if chg > 0 then return UP elseif chg < 0 then return DOWN else return FLAT end end
local function fnum(n, d) if n == nil then return "--" end return ("%." .. (d or 2) .. "f"):format(n) end

-- 读取数据
local idx, wl, kl = {}, {}, nil
for line in io.lines(dataf) do
    local parts = {}
    for p in (line .. "\t"):gmatch("([^\t]*)\t") do parts[#parts + 1] = p end
    if parts[1] == "IDX" then
        idx[#idx + 1] = { name = parts[2], price = tonumber(parts[3]), chg = tonumber(parts[4]) or 0,
                          pct = tonumber(parts[5]) or 0, open = tonumber(parts[6]), high = tonumber(parts[7]), low = tonumber(parts[8]) }
    elseif parts[1] == "WL" then
        wl[#wl + 1] = { name = parts[2], price = tonumber(parts[3]), chg = tonumber(parts[4]) or 0, pct = tonumber(parts[5]) or 0 }
    elseif parts[1] == "K" then
        local cs = {}
        for v in (parts[3] or ""):gmatch("[^,]+") do cs[#cs + 1] = tonumber(v) end
        kl = { name = parts[2], closes = cs }
    end
end

-- 标题栏
rect(0, 0, W, 88, "#0b1220")
text(36, 60, title, 40, "#ffffff")
text(0, 34, os.date("%Y-%m-%d %H:%M"), 24, "#9fb0c8", FEN, "NorthEast")

-- 指数卡片
local m, gap = 28, 18
local n = math.max(1, #idx)
local cw = math.floor((W - 2 * m - (n - 1) * gap) / n)
local cy, chh = 108, 192
for i, it in ipairs(idx) do
    local x1 = m + (i - 1) * (cw + gap)
    local x2 = x1 + cw
    rect(x1, cy, x2, cy + chh, PANEL)
    local col = ccol(it.chg)
    text(x1 + 20, cy + 16, it.name, 24, GRAY)
    text(x1 + 18, cy + 48, fnum(it.price), 56, col, FEN)
    text(x1 + 22, cy + 118, cnum(it.chg) .. "    " .. cnum(it.pct) .. "%", 26, col, FEN)
    if it.open then
        text(x1 + 20, cy + 152, "开" .. fnum(it.open) .. "  高" .. fnum(it.high) .. "  低" .. fnum(it.low), 19, GRAY)
    end
end

-- 面板起点
local py = cy + chh + 24
local pbot = H - 40
-- 左：自选股
local lx, lw = m, math.floor(W * 0.36)
rect(lx, py, lx + lw, pbot, PANEL)
text(lx + 24, py + 46, "自选股", 32, TXT)
text(lx + 24, py + 88, "名称", 22, GRAY)
text(lx + lw - 260, py + 88, "现价", 22, GRAY)
text(lx + lw - 110, py + 88, "涨跌幅", 22, GRAY)
local ry = py + 128
for _, it in ipairs(wl) do
    if ry > pbot - 10 then break end
    local col = ccol(it.chg)
    text(lx + 24, ry, it.name, 28, TXT)
    text(lx + lw - 260, ry, fnum(it.price), 28, TXT, FEN)
    text(lx + lw - 110, ry, cnum(it.pct) .. "%", 28, col, FEN)
    ry = ry + 44
end

-- 右：小K线
local rx = lx + lw + gap
local rw = W - m - rx
rect(rx, py, rx + rw, pbot, PANEL)
local kn = kl and kl.name or "走势"
text(rx + 24, py + 46, kn .. " · 近" .. (kl and #kl.closes or 0) .. "日", 32, TXT)
if kl and #kl.closes >= 2 then
    local cs = kl.closes
    local lo, hi = cs[1], cs[1]
    for _, v in ipairs(cs) do if v < lo then lo = v end if v > hi then hi = v end end
    if hi == lo then hi = lo + 1 end
    local gx1, gy1 = rx + 30, py + 96
    local gx2, gy2 = rx + rw - 120, pbot - 46
    local gw, gh = gx2 - gx1, gy2 - gy1
    -- 网格
    for k = 0, 4 do
        local yy = gy1 + math.floor(gh * k / 4)
        add("-stroke", qt(GRID), "-strokewidth", "1", "-fill", "none", "-draw", qt(("line %d,%d %d,%d"):format(gx1, yy, gx2, yy)))
    end
    local colK = (cs[#cs] >= cs[1]) and UP or DOWN
    local pts = {}
    for i, v in ipairs(cs) do
        local x = gx1 + math.floor(gw * (i - 1) / (#cs - 1))
        local y = gy2 - math.floor(gh * (v - lo) / (hi - lo))
        pts[#pts + 1] = x .. "," .. y
    end
    add("-stroke", qt(colK), "-strokewidth", "3", "-fill", "none", "-draw", qt("polyline " .. table.concat(pts, " ")))
    text(gx2 + 8, gy1 + 18, fnum(hi), 20, GRAY, FEN)
    text(gx2 + 8, gy2, fnum(lo), 20, GRAY, FEN)
    text(gx1, gy2 + 34, "同花顺数据", 18, GRAY)
end

-- 页脚
text(m, H - 30, "同花顺 · " .. os.date("%Y-%m-%d %H:%M:%S"), 18, GRAY)

qt_out = qt(out)
cmd[#cmd + 1] = qt_out
os.execute(table.concat(cmd, " "))
