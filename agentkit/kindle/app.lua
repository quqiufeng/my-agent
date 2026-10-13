-- kindle-ui：书架 + 阅读器（常驻控件 + show/hide，稳定重绘）
local exts={mobi=1,azw3=1,azw=1,pdf=1,epub=1,txt=1}
local function ls_books()
  local t={}; local p=io.popen("ls -1 /mnt/us/documents 2>/dev/null")
  if p then for l in p:lines() do local e=l:match("%.(%w+)$"); if e and exts[e:lower()] then t[#t+1]=l end end p:close() end
  return t
end
local function load_text(n) local f=io.open("/mnt/us/ui/books/"..n..".txt"); if not f then return nil end local s=f:read("*a"); f:close(); return s end
local function wrap(par,maxw)
  local out,cur,cw={},"",0
  for c in par:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local w=(#c>1) and 2 or 1
    if cw+w>maxw and cur~="" then out[#out+1]=cur;cur="";cw=0 end
    cur=cur..c; cw=cw+w
  end
  if cur~="" then out[#out+1]=cur end
  return out
end
local W={}; local mode="shelf"; local lines,npages,page; local books,sel
local function mk(t,x,y,sz,gray) local o=ui.text(x,y,t,sz); if gray then ui.color(o,gray) end return o end
local function initui()
  W.re_eyebrow=mk("K I N D L E · 阅 读",46,58,16,0x999999)
  W.re_title=mk("",46,106,34)
  W.re_hr1=ui.hr(46,172,732)
  W.re_body=mk("",46,194,26); ui.style(W.re_body,14,1)
  W.re_hr2=ui.hr(46,1078,732)
  W.re_page=mk("",46,1098,17,0x888888)
  W.re_hint=mk("← → 翻页    ·    HOME 书架",470,1098,17,0xaaaaaa)
  W.sh_title=mk("书架 · 我的电子书",0,0,34); ui.align(W.sh_title,ui.ALIGN_TOP_MID,0,44)
  W.sh_list=mk("",46,150,26); ui.style(W.sh_list,18,1)
  W.sh_hint=mk("↑ ↓ 选择    ·    中键打开",46,1120,17,0xaaaaaa)
end
local function showreader(b)
  for _,o in ipairs({W.re_eyebrow,W.re_title,W.re_hr1,W.re_body,W.re_hr2,W.re_page,W.re_hint}) do ui.show(o,b) end
  for _,o in ipairs({W.sh_title,W.sh_list,W.sh_hint}) do ui.show(o,not b) end
end
function render_list()
  local t={}
  for i,n in ipairs(books) do t[#t+1]=(i==sel and "▶ " or "    ")..n end
  ui.set(W.sh_list, table.concat(t,"\n")); ui.log("shelf sel="..sel)
end
function render()
  local t={}
  for i=(page-1)*19+1, math.min(page*19,#lines) do t[#t+1]=lines[i] end
  ui.set(W.re_body, table.concat(t,"\n"))
  ui.set(W.re_page,"第 "..page.." / "..npages.." 页"); ui.log("page "..page.."/"..npages)
end
function shelf()
  mode="shelf"; books=ls_books(); if #books==0 then books={"（空）"} end; sel=1
  showreader(false); render_list()
end
function open_book(name)
  local txt=load_text(name); if not txt then ui.log("no-text "..name); return end
  lines={}; for par in (txt:gsub("\r","").."\n"):gmatch("(.-)\n") do
    if par:match("^%s*$") then lines[#lines+1]="" else for _,l in ipairs(wrap("　　"..par,56)) do lines[#lines+1]=l end end
  end
  npages=math.max(1,math.ceil(#lines/19)); page=1; mode="reader"
  ui.set(W.re_title,name:gsub("%.%w+$","")); showreader(true); render(); ui.log("open "..name)
end
on_key=function(k)
  if mode=="reader" then
    if k=="right" or k=="down" or k=="enter" then if page<npages then page=page+1; render() end
    elseif k=="left" or k=="up" then if page>1 then page=page-1; render() end
    elseif k=="home" or k=="back" then shelf() end
  else
    if k=="down" or k=="right" then if sel<#books then sel=sel+1; render_list() end
    elseif k=="up" or k=="left" then if sel>1 then sel=sel-1; render_list() end
    elseif k=="enter" then open_book(books[sel]) end
  end
end
initui(); shelf()
