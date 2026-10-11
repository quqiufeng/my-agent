-- operator/report/github_trending.lua — 生成「GitHub 今日热门」Kami HTML
-- 用法: luajit github_trending.lua <out.html> [since] [lang] [limit]
-- 数据: agentkit/adapters/github.lua（curl 取 HTML + Lua 解析）
package.path = "/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;" .. package.path

local out    = arg[1] or "/tmp/github_trending.html"
local since  = arg[2] or "daily"
local lang   = arg[3] or ""
local limit  = tonumber(arg[4] or "15") or 15
local CSS    = "/opt/my-agent/operator/report/kami.css"

local ak = require("agentkit")
local gh = ak.app("github")
local list = gh.trending({ since = since, lang = lang, limit = limit })

local since_cn = ({ daily = "今日", weekly = "本周", monthly = "本月" })[since] or since
local function esc(s) return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

local css = ""
local f = io.open(CSS)
if f then css = f:read("*a"); f:close() end

local items = {}
for _, r in ipairs(list) do
    items[#items + 1] = ([[
      <li>
        <div class="row">
          <span class="repo">%s</span>
          <span class="stat">+%d <span class="star">★</span> <span class="dim">%s</span></span>
        </div>
        <div class="desc muted">%s</div>
      </li>]]):format(esc(r.repo), r.stars_today or 0, esc(r.lang or "—"), esc(r.desc))
end

local html = ([[<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>GitHub %s热门</title><style>%s</style>
<style>
 ol.tr{list-style:none;padding-left:0;counter-reset:t}
 ol.tr>li{counter-increment:t;position:relative;padding:8px 0 10px 34px;border-bottom:1px solid var(--hairline)}
 ol.tr>li::before{content:counter(t);position:absolute;left:0;top:9px;font-family:var(--mono);
   font-size:12px;color:var(--stone);font-variant-numeric:tabular-nums}
 .row{display:flex;justify-content:space-between;align-items:baseline;gap:16px}
 .repo{font-size:16px;font-weight:500}
 .stat{font-family:var(--mono);font-size:12px;color:var(--brand);white-space:nowrap}
 .stat .star{color:var(--brand)}
 .dim{color:var(--stone)}
 .desc{font-size:13.5px;line-height:1.5;margin-top:3px}
</style></head>
<body><div class="page">
  <div class="head">
    <div><div class="eyebrow">GITHUB TRENDING</div>
      <h1>GitHub %s热门</h1></div>
    <div class="meta">%s</div>
  </div>
  <hr class="hairline">
  <p class="lede">%s GitHub Trending 前 %d 个项目%s。</p>
  <ol class="tr">%s</ol>
  <div class="footer"><span>my-agent · GitHub %s热门</span><span>github.com/trending</span></div>
</div></body></html>]]):format(
    since_cn, css, since_cn, os.date("%Y-%m-%d · %A"),
    since_cn, #list, (lang ~= "" and ("（" .. esc(lang) .. "）") or ""),
    table.concat(items), since_cn)

local w = assert(io.open(out, "w")); w:write(html); w:close()
io.stderr:write(string.format("生成 %d 条 → %s\n", #list, out))
