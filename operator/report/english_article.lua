-- operator/report/english_article.lua — 双语精读 → Kami HTML + 文本
-- 用法: luajit english_article.lua <out.html> <out.txt> <jsonfile>
-- json: {"title_en","title_zh","paras":[{"en","zh"}],"vocab":[{"word","zh"}]}
local out_html, out_txt, jsf = arg[1], arg[2], arg[3]
local cjson = require("cjson")
local CSS = "/opt/my-agent/operator/report/kami.css"

local raw = ""
do local f = io.open(jsf); if f then raw = f:read("*a") or ""; f:close() end end
raw = raw:gsub("^%s*```%w*%s*", ""):gsub("%s*```%s*$", "")   -- 去可能的代码围栏
local ok, data = pcall(cjson.decode, raw)
if not ok or type(data) ~= "table" then data = { title_en = "", title_zh = "", paras = {}, vocab = {} } end

local function esc(s) return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
local te = data.title_en or ""; local tz = data.title_zh or ""
local paras = data.paras or {}; local vocab = data.vocab or {}

-- 文本
do local w = assert(io.open(out_txt, "w"))
   w:write(te .. (tz ~= "" and ("  " .. tz) or "") .. "\n\n")
   for _, p in ipairs(paras) do w:write((p.en or "") .. "\n" .. (p.zh or "") .. "\n\n") end
   if #vocab > 0 then w:write("生词：\n"); for _, v in ipairs(vocab) do w:write(string.format("  %s — %s\n", v.word or "", v.zh or "")) end end
   w:close() end

local css = ""; do local f = io.open(CSS); if f then css = f:read("*a"); f:close() end end
local body = {}
for _, p in ipairs(paras) do
    body[#body+1] = '<p class="en">' .. esc(p.en) .. '</p><p class="zh">' .. esc(p.zh) .. '</p>'
end
local vhtml = ""
if #vocab > 0 then
    local lis = {}
    for _, v in ipairs(vocab) do lis[#lis+1] = '<li><b>' .. esc(v.word) .. '</b> <span class="muted">' .. esc(v.zh) .. '</span></li>' end
    vhtml = '<h2>生词</h2><ul class="voc">' .. table.concat(lis) .. '</ul>'
end
local html = ([[<!doctype html><html lang="en"><head><meta charset="utf-8"><title>%s</title><style>%s</style>
<style>
 h1{font-size:26px;line-height:1.25;margin:.2em 0 .1em}
 .sub{font-size:17px;color:var(--muted);margin:0 0 4px}
 .en{font-size:16.5px;line-height:1.7;margin:1.1em 0 .15em;letter-spacing:0}
 .zh{font-size:15px;line-height:1.75;color:var(--muted);margin:.05em 0 1.1em;letter-spacing:.3pt}
 .voc{columns:2;column-gap:32px;font-size:14.5px;line-height:1.9;list-style:none;padding-left:0}
 .voc b{font-weight:500}
</style></head><body><div class="page">
  <div class="eyebrow">ENGLISH · 双语精读</div>
  <h1>%s</h1><div class="sub">%s</div>
  <hr class="hairline">
  %s
  %s
  <div class="footer"><span>my-agent · 每日英语</span><span>%s</span></div>
</div></body></html>]]):format(
    esc(te), css, esc(te), esc(tz), table.concat(body), vhtml, os.date("%Y-%m-%d"))
local wh = assert(io.open(out_html, "w")); wh:write(html); wh:close()
