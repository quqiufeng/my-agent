-- operator/report/weibo_hot.lua — 微博热搜 → Kami HTML + 文本
-- 用法: luajit weibo_hot.lua <out.html> <out.txt> <tsv>   (tsv 行: rank\tword\tnum)
local out_html = arg[1]; local out_txt = arg[2]; local tsv = arg[3]
local CSS = "/opt/my-agent/operator/report/kami.css"

local function esc(s) return (tostring(s or ""):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;")) end
local function fmtnum(n)
    n = tonumber(n) or 0
    if n >= 100000000 then return string.format("%.1f亿", n/1e8) end
    if n >= 10000 then return string.format("%.1f万", n/1e4) end
    return tostring(n)
end

local rows = {}
local f = io.open(tsv)
if f then for line in f:lines() do
    local r, w, n = line:match("^(%d+)\t(.-)\t(.*)$")
    if w and w ~= "" then rows[#rows+1] = { word = w, num = n } end
end f:close() end

-- 文本
do local w = assert(io.open(out_txt, "w"))
   w:write("【微博热搜】\n")
   for i, r in ipairs(rows) do w:write(string.format("%d. %s（%s）\n", i, r.word, fmtnum(r.num))) end
   w:close() end

-- HTML
local css = ""
do local f2 = io.open(CSS); if f2 then css = f2:read("*a"); f2:close() end end
local lis = {}
for i, r in ipairs(rows) do
    lis[#lis+1] = ([[
    <li><div class="row"><span class="repo">%s</span><span class="stat">%s</span></div></li>]]):format(esc(r.word), esc(fmtnum(r.num)))
end
local html = ([[<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<title>微博热搜</title><style>%s</style>
<style>
 ol.tr{list-style:none;padding-left:0;counter-reset:t}
 ol.tr>li{counter-increment:t;position:relative;padding:9px 0 9px 40px;border-bottom:1px solid var(--hairline)}
 ol.tr>li::before{content:counter(t);position:absolute;left:0;top:10px;font-family:var(--mono);font-size:13px;
   color:var(--stone);font-variant-numeric:tabular-nums}
 .row{display:flex;justify-content:space-between;align-items:baseline;gap:16px}
 .repo{font-size:16px;font-weight:500}
 .stat{font-family:var(--mono);font-size:12.5px;color:var(--brand);white-space:nowrap}
</style></head><body><div class="page">
  <div class="head"><div><div class="eyebrow">WEIBO · 热搜榜</div><h1>微博热搜</h1></div>
    <div class="meta">%s</div></div>
  <hr class="hairline">
  <p class="lede">实时热搜 共 %d 条。</p>
  <ol class="tr">%s</ol>
  <div class="footer"><span>my-agent · 微博热搜</span><span>s.weibo.com</span></div>
</div></body></html>]]):format(css, os.date("%Y-%m-%d %H:%M"), #rows, table.concat(lis))
local wh = assert(io.open(out_html, "w")); wh:write(html); wh:close()
