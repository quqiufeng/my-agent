-- operator/report/gemini_report.lua — Google AI(Gemini) 问答 → Kami HTML + 文本
-- 用法: luajit gemini_report.lua <out.html> <out.txt> <问题> <回答文件>
package.path = "/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;" .. package.path
local out_html = arg[1]; local out_txt = arg[2]; local q = arg[3] or ""; local af = arg[4]
local CSS = "/opt/my-agent/operator/report/kami.css"

local ans = ""
if af then local f = io.open(af); if f then ans = f:read("*a") or ""; f:close() end end
local function esc(s) return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
local css = ""
do local f = io.open(CSS); if f then css = f:read("*a"); f:close() end end

-- 纯文本
do local w = assert(io.open(out_txt, "w"))
   w:write("【Google AI 回答】\n问：" .. q .. "\n\n" .. ans .. "\n"); w:close() end

local html = ([[<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<title>Google AI</title><style>%s</style>
<style>.qa{white-space:pre-wrap;font-size:15.5px;line-height:1.7;letter-spacing:.3pt}
.q{font-size:17px;font-weight:500;line-height:1.5;margin:.2em 0 .2em}</style>
</head><body><div class="page">
 <div class="head"><div><div class="eyebrow">GOOGLE AI · GEMINI</div><h1>Google AI 回答</h1></div>
   <div class="meta">%s</div></div>
 <hr class="hairline">
 <p class="q">问：%s</p>
 <div class="qa">%s</div>
 <div class="footer"><span>my-agent · Google AI</span><span>gemini.google.com</span></div>
</div></body></html>]]):format(css, os.date("%Y-%m-%d · %A"), esc(q), esc(ans))
local wh = assert(io.open(out_html, "w")); wh:write(html); wh:close()
