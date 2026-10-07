-- operator/tools/dash_html.lua — 生成「点阵风」行情大屏 HTML（供 headless Chrome 截图）
-- 用法: luajit dash_html.lua <data.tsv> <out.html> [title]
-- data.tsv 行（TAB 分隔）:
--   IDX 名称 现价 涨跌 涨跌幅 今开 最高 最低
--   WL  名称 现价 涨跌 涨跌幅
--   K   名称 收盘1,收盘2,...
-- 依赖 dotkit/dot-ui.css|js（karminski-design-skills，CC BY-NC-SA 4.0，见 dotkit/NOTICE.md）
local dataf = arg[1] or "/tmp/myagent_dash.tsv"
local outf  = arg[2] or "/tmp/myagent_dash.html"
local title = arg[3] or "行情大屏"
local KIT   = "/opt/my-agent/operator/tools/dotkit"

-- ── 读数据 ──────────────────────────────────────────────────
local idx, wl, kl = {}, {}, nil
for line in io.lines(dataf) do
    local p = {}
    for x in (line .. "\t"):gmatch("([^\t]*)\t") do p[#p + 1] = x end
    if p[1] == "IDX" then
        idx[#idx + 1] = { name = p[2], price = tonumber(p[3]), chg = tonumber(p[4]) or 0,
                          pct = tonumber(p[5]) or 0, open = tonumber(p[6]), high = tonumber(p[7]), low = tonumber(p[8]) }
    elseif p[1] == "WL" then
        wl[#wl + 1] = { name = p[2], price = tonumber(p[3]), chg = tonumber(p[4]) or 0, pct = tonumber(p[5]) or 0 }
    elseif p[1] == "K" then
        local cs = {}
        for v in (p[3] or ""):gmatch("[^,]+") do cs[#cs + 1] = tonumber(v) end
        kl = { name = p[2], closes = cs }
    end
end

-- ── 工具 ────────────────────────────────────────────────────
local function esc(s)
    s = tostring(s or "")
    return (s:gsub("[&<>]", function(c) return ({ ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" })[c] end))
end
local function f2(n) if not n then return "--" end return string.format("%.2f", n) end
local function sgn(n) if not n then return "--" end return (n >= 0 and "+%.2f" or "%.2f"):format(n) end
local function cls(chg) if chg > 0 then return "up" elseif chg < 0 then return "down" else return "flat" end end
local function col(chg) if chg > 0 then return "#d92121" elseif chg < 0 then return "#2e8b57" else return "#5b6b4f" end end

-- 涨跌幅统一的 bar 量程（行间可比较）
local maxabs = 4
for _, it in ipairs(idx) do maxabs = math.max(maxabs, math.abs(it.pct)) end
for _, it in ipairs(wl) do maxabs = math.max(maxabs, math.abs(it.pct)) end
local PMAX = math.ceil(maxabs)

-- 涨/跌/平 计数（状态行）
local up, down, flat = 0, 0, 0
for _, it in ipairs(idx) do if it.chg > 0 then up = up + 1 elseif it.chg < 0 then down = down + 1 else flat = flat + 1 end end
for _, it in ipairs(wl) do if it.chg > 0 then up = up + 1 elseif it.chg < 0 then down = down + 1 else flat = flat + 1 end end

local T = {}
local function w(s) T[#T + 1] = s end
local function barrow(it)
    w(('<div class="bar-row"><span>%s</span>'
        .. '<canvas data-dot="bar" data-value="%.2f" data-max="%d" data-size="3.4" data-color="%s"></canvas>'
        .. '<span class="value %s">%s<span class="unit"> %s%%</span></span></div>')
        :format(esc(it.name), math.abs(it.pct), PMAX, col(it.chg), cls(it.chg), f2(it.price), sgn(it.pct)))
end

-- ── 页面 ────────────────────────────────────────────────────
w('<!doctype html><html lang="zh"><head><meta charset="utf-8">')
w('<meta name="viewport" content="width=device-width, initial-scale=1">')
w('<title>' .. esc(title) .. '</title>')
w('<link rel="stylesheet" href="' .. KIT .. '/dot-ui.css">')
w([[<style>
  /* 中国传统色 · 霜地（浅色）：霜地 #E2F0CB 底 + 墨色字 + 黛蓝强调 + 朱砂红/青绿 */
  :root{
    --ink:#1d1b1c;--muted:#5b6b4f;--dim:#8a9a7e;--unlit:#b9cba0;--faint:#cbdab4;
    --accent:#2a3c5c;--accent-bg:#d6e4be;--warn:#c77a16;--crit:#d92121;--ok:#2e8b57;--err:#d92121;
    --card-top:#f3f8e8;--card-bottom:#e7f0d6;--card-border:#c4d6a6;
    --pill-bg:#eaf3d9;--pill-border:#c4d6a6;--hairline:#d6e2bd;
  }
  body{font-size:12px;background:radial-gradient(ellipse 120% 100% at 12% -8%, #f4fae9 0%, #e2f0cb 45%, #d2e3b4 100%) fixed #e2f0cb}
  .card{box-shadow:0 6px 20px rgba(90,110,70,.18)}
  .up{color:#d92121}.down{color:#2e8b57}.flat{color:#5b6b4f}
  .hero{align-items:center}
  .bar-row{grid-template-columns:96px 1fr 118px;margin-bottom:9px}
  .section{margin-top:14px}
  .stat-grid{grid-template-columns:repeat(3,1fr)}
</style>]])
w('</head><body>')

-- 头部
w('<header class="page-header"><div>')
w('<canvas data-dot="text" data-text="A-SHARE" data-size="4.6" data-gap="1.7"></canvas>')
w('<div class="subtitle">同花顺 · ' .. esc(title) .. ' · ' .. os.date("%Y-%m-%d %H:%M") .. '</div>')
w(('<div class="status"><span class="status-dot"></span><span>%d 涨 · %d 跌 · %d 平</span></div>')
    :format(up, down, flat))
w('</div>')
w('<div class="header-right">')
w('<canvas id="clock" data-dot="text" data-text="' .. os.date("%H:%M:%S") .. '" data-size="2.8" data-gap="1.1"></canvas>')
w('<div class="caption">DATA · 同花顺</div>')
w('</div></header>')

w('<main class="page-body"><div class="masonry">')

-- 01 上证指数（hero：环 + 统计 + 走势）
local main = idx[1]
w('<section class="card">')
w('<div class="card-head"><span class="card-num">01</span><span class="card-title">指数 · 上证</span>'
    .. '<span class="badge">' .. (main and esc(main.name) or "--") .. '</span></div>')
if main then
    local lo, hi = main.low or main.price, main.high or main.price
    if hi <= lo then hi = lo + 1 end
    w('<div class="hero"><div class="ring">')
    w(('<canvas data-dot="ring" data-value="%.2f" data-min="%.2f" data-max="%.2f" data-color="%s"></canvas>')
        :format(main.price or 0, lo, hi, col(main.chg)))
    w('<div class="ring-center">')
    w(('<canvas data-dot="text" data-text="%s" data-size="3.4" data-gap="1.3" data-color="%s"></canvas>')
        :format(main.price and string.format("%.0f", main.price) or "--", col(main.chg)))
    w('<div class="unit">点</div><div class="ring-caption">000001.SH</div>')
    w('</div></div>')
    w('<div class="stats">')
    w(('<div class="gauge"><div class="gauge-head"><span class="caption">涨跌幅</span>'
        .. '<span class="value %s">%s<span class="unit"> %%</span></span></div>'
        .. '<canvas data-dot="bar" data-value="%.2f" data-max="%d" data-color="%s"></canvas></div>')
        :format(cls(main.chg), sgn(main.pct), math.abs(main.pct), PMAX, col(main.chg)))
    w('<div class="stat-grid">')
    w(('<div><div class="caption">涨跌</div><div class="value %s">%s</div></div>'):format(cls(main.chg), sgn(main.chg)))
    w(('<div><div class="caption">今开</div><div class="value">%s</div></div>'):format(f2(main.open)))
    w(('<div><div class="caption">最高</div><div class="value">%s</div></div>'):format(f2(main.high)))
    w(('<div><div class="caption">最低</div><div class="value">%s</div></div>'):format(f2(main.low)))
    w(('<div><div class="caption">现价</div><div class="value %s">%s</div></div>'):format(cls(main.chg), f2(main.price)))
    w('</div></div></div>')
    -- 走势
    if kl and kl.closes and #kl.closes >= 2 then
        local cs = kl.closes
        local lo2, hi2 = cs[1], cs[1]
        for _, v in ipairs(cs) do if v < lo2 then lo2 = v end; if v > hi2 then hi2 = v end end
        if hi2 <= lo2 then hi2 = lo2 + 1 end
        w('<div class="section"><div class="caption">上证走势 · 近' .. #cs .. '日</div>')
        w(('<canvas data-dot="sparkline" data-values="%s" data-min="%.2f" data-max="%.2f" data-color="%s"></canvas>')
            :format(table.concat(cs, ","), lo2, hi2, col(cs[#cs] - cs[1])))
        w('</div>')
    end
else
    w('<div class="message">No data</div>')
end
w('</section>')

-- 02 主要指数（其余）
w('<section class="card">')
w('<div class="card-head"><span class="card-num">02</span><span class="card-title">主要指数</span>'
    .. '<span class="badge">' .. math.max(0, #idx - 1) .. ' × INDEX</span></div>')
if #idx > 1 then for i = 2, #idx do barrow(idx[i]) end else w('<div class="message">No data</div>') end
w('</section>')

-- 03 自选股
w('<section class="card">')
w('<div class="card-head"><span class="card-num">03</span><span class="card-title">自选股</span>'
    .. '<span class="badge">' .. #wl .. ' × STOCK</span></div>')
if #wl > 0 then for _, it in ipairs(wl) do barrow(it) end else w('<div class="message">No data</div>') end
w('</section>')

-- 04 涨跌分布（点阵柱）
local all = {}
for _, it in ipairs(idx) do all[#all + 1] = it end
for _, it in ipairs(wl) do all[#all + 1] = it end
table.sort(all, function(a, b) return a.pct > b.pct end)
do
    local vals, names = {}, {}
    for _, it in ipairs(all) do
        vals[#vals + 1] = string.format("%.2f", math.abs(it.pct))
        names[#names + 1] = esc(it.name)
    end
    w('<section class="card">')
    w('<div class="card-head"><span class="card-num">04</span><span class="card-title">涨跌分布</span>'
        .. '<span class="badge">' .. #all .. ' × 标的</span></div>')
    w('<div class="caption">按涨跌幅排序（左大右小）</div>')
    w(('<canvas data-dot="columns" data-values="%s" data-max="%d" data-rows="8" style="margin-top:10px"></canvas>')
        :format(table.concat(vals, ","), PMAX))
    w('<div class="caption" style="margin-top:10px">'
        .. (names[1] or "") .. ' … ' .. (names[#names] or "") .. '</div>')
    w('</section>')
end

-- 05 全部行情（整宽，三列）
w('</div>')  -- 关闭 masonry
w('<section class="card" style="margin-top:var(--gap)">')
w('<div class="card-head"><span class="card-num">05</span><span class="card-title">全部行情</span>'
    .. '<span class="badge">' .. #all .. ' × ALL · 按涨幅</span></div>')
if #all > 0 then
    w('<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));column-gap:30px">')
    for _, it in ipairs(all) do barrow(it) end
    w('</div>')
else
    w('<div class="message">No data</div>')
end
w('</section>')

w('</main>')

-- 页脚
w('<footer class="page-footer"><div><div class="tagline">STAY FOCUSED, TRADE SMART_</div>'
    .. '<div style="margin-top:7px;color:var(--dim)">同花顺数据 · ' .. os.date("%Y-%m-%d %H:%M:%S") .. '</div></div>'
    .. '<div>dot-matrix ui · karminski</div></footer>')

w('<script src="' .. KIT .. '/dot-ui.js"></script>')
w([[<script>
Object.assign(DotUI.palette,{ink:"#1d1b1c",unlit:"#b9cba0",faint:"#cbdab4",accent:"#2a3c5c",warning:"#c77a16",critical:"#d92121"});
DotUI.mount();
</script>]])
w('</body></html>')

local f = assert(io.open(outf, "w"))
f:write(table.concat(T, "\n"))
f:close()
print(outf)
