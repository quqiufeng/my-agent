-- operator/report/google_report.lua — 谷歌结果 → Kami HTML + 纯文本（一次搜索）
-- 用法: luajit google_report.lua <out.html> <out.txt> <关键词> [search|news]
package.path = "/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;" .. package.path

local out_html = arg[1] or "/tmp/gg.html"
local out_txt  = arg[2] or "/tmp/gg.txt"
local kw       = arg[3] or ""
local mode     = arg[4] or "search"
local CSS      = "/opt/my-agent/operator/report/kami.css"

local ak = require("agentkit")
local g = ak.app("google")
if mode == "news" then g.news(kw) else g.search(kw) end
os.execute("sleep 3")

local items, panel
if mode == "news" then items = g.news_results(15) else items = g.results(15); panel = g.panel() end

local function esc(s) return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
local title_cn = (mode == "news") and "Google 新闻" or "Google 搜索"

-- 纯文本
local tl = { "【" .. title_cn .. "：" .. kw .. "】" }
for i, r in ipairs(items) do
    local src = r.source or r.cite or r.url_real or r.url or ""
    tl[#tl + 1] = string.format("%d. %s —— %s", i, r.title, src)
    if r.snippet and r.snippet ~= "" then tl[#tl + 1] = "    " .. r.snippet end
end
if panel and panel ~= "" then tl[#tl + 1] = "◆ 百科： " .. panel:gsub("\n", " ") end
local w = assert(io.open(out_txt, "w")); w:write(table.concat(tl, "\n") .. "\n"); w:close()

-- HTML（Kami）
local css = ""
local f = io.open(CSS); if f then css = f:read("*a"); f:close() end
local lis = {}
for i, r in ipairs(items) do
    local src = r.source or r.cite or r.url_real or r.url or ""
    lis[#lis + 1] = ([[
    <li>
      <div class="row"><span class="repo">%s</span><span class="src">%s</span></div>
      <div class="desc muted">%s</div>
    </li>]]):format(esc(r.title), esc(src), esc(r.snippet))
end
local panel_html = ""
if panel and panel ~= "" then
    panel_html = '<h2>百科</h2><div class="card"><p class="muted" style="margin:0;white-space:pre-wrap">' ..
        esc(panel) .. "</p></div>"
end

local html = ([[<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<title>%s</title><style>%s</style>
<style>
 ol.tr{list-style:none;padding-left:0;counter-reset:t}
 ol.tr>li{counter-increment:t;position:relative;padding:8px 0 10px 34px;border-bottom:1px solid var(--hairline)}
 ol.tr>li::before{content:counter(t);position:absolute;left:0;top:9px;font-family:var(--mono);font-size:12px;color:var(--stone)}
 .row{display:flex;justify-content:space-between;align-items:baseline;gap:16px}
 .repo{font-size:15.5px;font-weight:500}
 .src{font-family:var(--mono);font-size:12px;color:var(--brand);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:46%%}
 .desc{font-size:13.5px;line-height:1.5;margin-top:3px}
</style></head><body><div class="page">
  <div class="head"><div><div class="eyebrow">GOOGLE · %s</div><h1>%s：%s</h1></div>
    <div class="meta">%s</div></div>
  <hr class="hairline">
  <p class="lede">共 %d 条结果。</p>
  <ol class="tr">%s</ol>
  %s
  <div class="footer"><span>my-agent · %s</span><span>google.com</span></div>
</div></body></html>]]):format(
    esc(title_cn), css, (mode == "news" and "NEWS" or "SEARCH"), esc(title_cn), esc(kw),
    os.date("%Y-%m-%d · %A"), #items, table.concat(lis), panel_html, esc(title_cn))

local wh = assert(io.open(out_html, "w")); wh:write(html); wh:close()
io.stderr:write(string.format("生成 %d 条 → %s / %s\n", #items, out_html, out_txt))
