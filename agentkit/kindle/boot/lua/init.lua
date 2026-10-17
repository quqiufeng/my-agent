-- kindle-ui v2：书架 + 阅读器
-- 功能：进度记忆/续读 · 中文标点排版 · 进度百分比 · 快速跳页 · 目录跳转 · 字号档位
local UIDIR   = "/mnt/us/ui/"
local BOOKDIR = UIDIR.."books/"
local POSFILE = UIDIR.."pos.lua"
local DOCDIR  = "/mnt/us/documents"
local exts    = {mobi=1,azw3=1,azw=1,pdf=1,epub=1,txt=1}

-- ===== 字号档位（fs=正文字号；ls=行距；title=标题字号）=====
local SIZES = {
  {name="小", fs=22, ls=8,  title=30},
  {name="中", fs=26, ls=14, title=34},
  {name="大", fs=34, ls=16, title=38},
}
local ssize = 2
local cur_lines = 19   -- 当前每页正文行数（paginate 时按字体实算）
-- 屏幕尺寸：Kindle 824x1200；手机 kiosk 用 UI_W/UI_H（Xvfb 720x1600）
local SW = tonumber(os.getenv("UI_W") or "") or 824
local SH = tonumber(os.getenv("UI_H") or "") or 1200
-- 正文可用区（W.r_body 起点 x=46,y=194；底部留给分隔线+页码）
local BODY_W, BODY_H = SW-92, SH-274
-- 按真实字体度量算：每行半角宽 maxw、每页行数 lines
local function size_metrics(sz)
  local cw    = ui.measure("汉", sz.fs)          -- 单个汉字宽 ≈ 字号
  local _, lh = ui.measure("汉", sz.fs)          -- 行高
  local maxw  = math.floor(BODY_W / (cw + 1)) * 2  -- letter_space=1
  local lines = math.floor(BODY_H / (lh + sz.ls))
  if maxw  < 10 then maxw  = 10 end
  if lines < 5  then lines = 5  end
  return maxw, lines
end

-- ===== 进度持久化 =====
local pos = {}; local last_book = nil
local function load_pos()
  local f = io.open(POSFILE,"r"); if not f then return end
  local s = f:read("*a"); f:close()
  local fn = loadstring(s)
  if fn then local ok,r = pcall(fn); if ok and type(r)=="table" then pos=r.pos or {}; last_book=r.last end end
end
local function save_pos()
  local t = {}
  for k,v in pairs(pos) do t[#t+1] = string.format("[%q]=%d",k,v) end
  local f = io.open(POSFILE,"w"); if not f then return end
  f:write("return {pos={"..table.concat(t,",").."}, last="..(last_book and string.format("%q",last_book) or "nil").."}\n")
  f:close()
end

-- ===== 文件 =====
local function ls_books()
  local t={}; local p=io.popen("ls -1 '"..DOCDIR.."' 2>/dev/null")
  if p then for l in p:lines() do local e=l:match("%.(%w+)$"); if e and exts[e:lower()] then t[#t+1]=l end end p:close() end
  return t
end
local function load_text(n)
  local f=io.open(BOOKDIR..n..".txt"); if f then local s=f:read("*a"); f:close(); return s end
  if n:lower():match("%.txt$") then
    local f2=io.open(DOCDIR.."/"..n); if f2 then local s=f2:read("*a"); f2:close(); return s end
  end
  return nil
end

-- ===== 排版：UTF-8 感知换行 + 中文标点避头尾 =====
local NO_START = {["，"]=1,["。"]=1,["、"]=1,["；"]=1,["："]=1,["？"]=1,["！"]=1,["）"]=1,["】"]=1,["》"]=1,["」"]=1,["』"]=1,["…"]=1,["％"]=1,["·"]=1,[","]=1,["."]=1,["!"]=1,["?"]=1,[")"]=1,["]"]=1,["}"]=1,[":"]=1,[";"]=1}
local NO_END   = {["（"]=1,["【"]=1,["《"]=1,["「"]=1,["『"]=1,["<"]=1,["("]=1,["["]=1,["{"]=1}
local function utf8_chars(s) local t={} for c in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t+1]=c end return t end
local function w1(c) return (#c>1) and 2 or 1 end
local function wrap(par,maxw)
  local cs=utf8_chars(par); local out={}; local cur=""; local cw=0
  for i=1,#cs do
    local c=cs[i]; local w=w1(c)
    if cur~="" and cw+w>maxw then out[#out+1]=cur; cur=""; cw=0 end
    cur=cur..c; cw=cw+w
  end
  if cur~="" then out[#out+1]=cur end
  for i=1,#out-1 do
    local a,b=out[i],out[i+1]
    local b1=b:match("^([\194-\244][\128-\191]*|.)")
    if b1 and NO_START[b1] and #b>#b1 then out[i]=a..b1; out[i+1]=b:sub(#b1+1) end
    a=out[i]
    local last=a:match("([\194-\244][\128-\191]*|.)$")
    if last and NO_END[last] then out[i]=a:sub(1,#a-#last); out[i+1]=last..out[i+1] end
  end
  return out
end
local function chapter_of(par)
  local t=par:match("^##%s*(.+)$"); if t then return t end
  if #par<=40 then
    if par:match("^第[%d零一二三四五六七八九十百千]+[章节回篇部卷]") then return par end
    if par:match("^[Cc]hapter%s*%d+") then return par end
    if par:match("^[Pp]art%s*%d+") then return par end
  end
  return nil
end

-- ===== 状态 =====
local W={}
local mode="shelf"
local lines, toc = {}, {}
local npages, page = 1, 1
local books, sel = {}, 1
local mitems, msel = {}, 1
local tsel = 1
local curname
local MAX_LINES = 50000   -- 单本书分页后的行数上限（防大书耗尽内存）

local function mk(t,x,y,sz,gray) local o=ui.text(x,y,t,sz); if gray then ui.color(o,gray) end return o end
local function initui()
  W.r_eyebrow = mk("K I N D L E · 阅 读",46,58,16,0x999999)
  W.r_title   = mk("",46,106,34)
  W.r_hr1     = ui.hr(46,172,BODY_W)
  W.r_body    = mk("",46,194,26); ui.style(W.r_body,SIZES[ssize].ls,1)
  W.r_hr2     = ui.hr(46,SH-80,BODY_W)
  W.r_page    = mk("",46,SH-54,17,0x777777)
  W.r_hint    = mk("← → 翻页  ↑ ↓ ±10页  · 中键 菜单",SW-464,SH-54,17,0xaaaaaa)
  W.l_title   = mk("",0,0,34); ui.align(W.l_title,ui.ALIGN_TOP_MID,0,44)
  W.l_body    = mk("",46,150,26); ui.style(W.l_body,18,1)
  W.l_hint    = mk("",46,SH-54,17,0xaaaaaa)
  W.lock      = mk("已锁定\n\n拨动顶部 lock 开关解锁", 0, 0, 34)
  ui.align(W.lock, ui.ALIGN_CENTER, 0, 0)
  ui.talign(W.lock, 1)   -- 文字居中
  ui.show(W.lock, false)
end
local function screen(which)
  for _,o in ipairs({W.r_eyebrow,W.r_title,W.r_hr1,W.r_body,W.r_hr2,W.r_page,W.r_hint}) do ui.show(o, which=="reader") end
  for _,o in ipairs({W.l_title,W.l_body,W.l_hint}) do ui.show(o, which=="list") end
  ui.full()   -- 切屏整页变，做一次全刷消残影
end

local function paginate(txt)
  local sz=SIZES[ssize]
  local maxw, nlines = size_metrics(sz)
  cur_lines = nlines
  -- 切字号必须同步改字体并重排（否则字号变了排版没变）
  ui.setfont(W.r_body,  sz.fs)
  ui.setfont(W.r_title, sz.title)
  ui.style(W.r_body, sz.ls, 1)
  ui.full()   -- 重排后整页变
  lines={}; toc={}
  txt = (txt or ""):gsub("\r","")
  for par in (txt.."\n"):gmatch("(.-)\n") do
    if par:match("^%s*$") then
      if #lines>0 and lines[#lines]~="" then lines[#lines+1]="" end
    else
      local ch = chapter_of(par)
      if ch then
        if #lines>0 and lines[#lines]~="" then lines[#lines+1]="" end
        toc[#toc+1] = {title=ch, line=#lines+1}
        lines[#lines+1] = "◆ "..ch
        lines[#lines+1] = ""
      else
        for _,l in ipairs(wrap("　　"..par, maxw)) do lines[#lines+1]=l end
      end
    end
    if #lines >= MAX_LINES then
      ui.log("WARN 文本过大，已截断到 "..MAX_LINES.." 行")
      break
    end
  end
  npages = math.max(1, math.ceil(#lines/nlines))
end

function render()
  local t={}
  for i=(page-1)*cur_lines+1, math.min(page*cur_lines,#lines) do t[#t+1]=lines[i] end
  ui.set(W.r_body, table.concat(t,"\n"))
  local pct=math.floor(page*100/npages+0.5)
  ui.set(W.r_page, "第 "..page.." / "..npages.." 页    "..pct.."%")
  local ch=""
  for _,c in ipairs(toc) do if c.line<= (page-1)*cur_lines+1 then ch=c.title else break end end
  ui.log("page "..page.."/"..npages.." "..pct.."% "..ch)
  if ui_save_state then ui_save_state() end
end

function open_book(name)
  local txt=load_text(name); if not txt then ui.log("no-text "..name); return end
  curname=name
  paginate(txt)
  txt=nil   -- 分页后释放整本书文本（内存紧张：设备仅 ~12MB free）
  page = pos[name] or 1
  if page<1 then page=1 end; if page>npages then page=npages end
  mode="reader"; last_book=name
  ui.set(W.r_title, name:gsub("%.%w+$",""))
  screen("reader"); render()
end

local function set_size(delta)
  local frac = npages>1 and (page-1)/(npages-1) or 0
  ssize = ((ssize-1+delta) % #SIZES) + 1
  local txt = curname and load_text(curname)
  if txt then
    paginate(txt)
    txt=nil
    page = math.floor(frac*(npages-1)+0.5)+1
    if page<1 then page=1 end; if page>npages then page=npages end
    pos[curname]=page; save_pos(); render()
  end
end

local function render_menu()
  local t={}
  for i,it in ipairs(mitems) do t[#t+1]=(i==msel and "→ " or "   ")..it.t end
  ui.set(W.l_title,"菜单"); ui.set(W.l_body, table.concat(t,"\n"))
  ui.set(W.l_hint,"↑ ↓ 选择  ·  中键 确定  ·  ← 返回")
  if ui_save_state then ui_save_state() end
end
function open_menu()
  mitems={}
  if #toc>0 then mitems[#mitems+1]={t="目录",a="toc"} end
  mitems[#mitems+1]={t="字号："..SIZES[ssize].name,a="size"}
  mitems[#mitems+1]={t="返回书架",a="shelf"}
  mitems[#mitems+1]={t="继续阅读",a="close"}
  msel=1; mode="menu"; screen("list"); render_menu()
end
local function render_toc()
  local t={}
  for i,c in ipairs(toc) do t[#t+1]=(i==tsel and "→ " or "   ")..c.title end
  ui.set(W.l_title,"目录"); ui.set(W.l_body, table.concat(t,"\n"))
  ui.set(W.l_hint,"↑ ↓ 选择  ·  中键 跳转  ·  ← 返回")
  if ui_save_state then ui_save_state() end
end
local function open_toc() mode="toc"; tsel=1; screen("list"); render_toc() end
local function toc_jump()
  if toc[tsel] then page=math.ceil(toc[tsel].line/cur_lines)
    if page<1 then page=1 end; if page>npages then page=npages end
    pos[curname]=page; save_pos(); mode="reader"; screen("reader"); render() end
end

local function render_list()
  local t={}
  for i,n in ipairs(books) do t[#t+1]=(i==sel and "→ " or "   ")..n end
  ui.set(W.l_title,"书架 · 我的电子书"); ui.set(W.l_body, table.concat(t,"\n"))
  ui.set(W.l_hint,"↑ ↓ 选择  ·  中键 打开  ·  上次："..(last_book or "—"))
  if ui_save_state then ui_save_state() end
end
function shelf()
  mode="shelf"; books=ls_books(); if #books==0 then books={"（空）"} end
  sel=1; if last_book then for i,b in ipairs(books) do if b==last_book then sel=i end end end
  screen("list"); render_list()
end

on_key=function(k)
  if k=="nextpage" then k="right" elseif k=="prevpage" then k="left" end
  if mode=="reader" then
    if k=="right" then if page<npages then page=page+1; pos[curname]=page; save_pos(); render() end
    elseif k=="left" then if page>1 then page=page-1; pos[curname]=page; save_pos(); render() end
    elseif k=="down" then page=math.min(npages,page+10); pos[curname]=page; save_pos(); render()
    elseif k=="up" then page=math.max(1,page-10); pos[curname]=page; save_pos(); render()
    elseif k=="enter" or k=="menu" then open_menu()
    elseif k=="home" or k=="back" then shelf() end
  elseif mode=="menu" then
    if k=="down" then if msel<#mitems then msel=msel+1; render_menu() end
    elseif k=="up" then if msel>1 then msel=msel-1; render_menu() end
    elseif k=="enter" then
      local a=mitems[msel].a
      if a=="toc" then open_toc()
      elseif a=="size" then set_size(1); render_menu()
      elseif a=="shelf" then shelf()
      else mode="reader"; screen("reader"); render() end
    elseif k=="left" or k=="back" or k=="home" then mode="reader"; screen("reader"); render() end
  elseif mode=="toc" then
    if k=="down" then if tsel<#toc then tsel=tsel+1; render_toc() end
    elseif k=="up" then if tsel>1 then tsel=tsel-1; render_toc() end
    elseif k=="enter" then toc_jump()
    elseif k=="left" or k=="back" or k=="home" then mode="reader"; screen("reader"); render() end
  else
    if k=="down" or k=="right" then if sel<#books then sel=sel+1; render_list() end
    elseif k=="up" or k=="left" then if sel>1 then sel=sel-1; render_list() end
    elseif k=="enter" then open_book(books[sel]) end
  end
end

-- 顶部 lock 开关：锁定时清屏显示锁定页，解锁后恢复原界面
local function restore_screen()
  if mode=="reader" then screen("reader"); render()
  elseif mode=="menu" then screen("list"); render_menu()
  elseif mode=="toc" then screen("list"); render_toc()
  else screen("list"); render_list() end
end

function on_lock(v)
  local on = v and true or false
  ui.log(on and "LOCK" or "UNLOCK")
  if on then
    for _,o in ipairs({W.r_eyebrow,W.r_title,W.r_hr1,W.r_body,W.r_hr2,W.r_page,W.r_hint,
                       W.l_title,W.l_body,W.l_hint}) do ui.show(o,false) end
    -- 优先显示锁屏图片；文件缺失时回退文字
    ui.full()
    if not ui.overlay("/mnt/us/ui/lock.gray") then ui.show(W.lock, true) end
  else
    ui.overlay(nil)
    ui.show(W.lock, false)
    restore_screen()
  end
  if ui_save_state then ui_save_state() end
end

-- 原始扫描码 → 名称（新版 lvgui 直接回调 on_code；无需 keyd）
local CODE = {[98]="home",[91]="back",[139]="menu",[109]="prevpage",[124]="nextpage",
              [122]="up",[123]="down",[92]="enter",[105]="left",[106]="right"}
function on_code(c) local k=CODE[c]; if k then on_key(k) end end

-- ===== agent 自动化接口（状态查询 / 按键模拟 / 读屏文本）=====
local CODE_BY_NAME = {}
for c,n in pairs(CODE) do CODE_BY_NAME[n]=c end

function ui_info()
  local item
  if mode=="menu" then item = mitems[msel] and mitems[msel].t
  elseif mode=="toc" then item = toc[tsel] and toc[tsel].title
  else item = books[sel] end
  return { mode=mode, page=page, npages=npages,
           pct=(npages>0 and math.floor(page*100/npages+0.5) or 0),
           size=SIZES[ssize].name, book=curname or "",
           books=#books, sel=sel,
           menu_n=#mitems, menu_sel=msel,
           toc_n=#toc, toc_sel=tsel, item=item or "" }
end

local function jesc(x) return (tostring(x):gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n")) end

function ui_state()
  local i=ui_info()
  return string.format(
    '{"mode":"%s","page":%d,"npages":%d,"pct":%d,"size":"%s","book":"%s","books":%d,"sel":%d,"menu_n":%d,"menu_sel":%d,"toc_n":%d,"toc_sel":%d,"item":"%s"}',
    jesc(i.mode), i.page, i.npages, i.pct, jesc(i.size), jesc(i.book),
    i.books, i.sel, i.menu_n, i.menu_sel, i.toc_n, i.toc_sel, jesc(i.item))
end

function ui_save_state()
  local s=ui_state()
  local f=io.open("/tmp/ui_state.json","w")
  if f then f:write(s.."\n"); f:close() end
  return s
end

-- 模拟一次按键（名称或原始扫描码），返回最新状态表
function tap(k)
  local c = (type(k)=="number") and k or CODE_BY_NAME[k]
  if c then on_code(c) end
  ui_save_state()
  return ui_info()
end

-- 当前页正文（只取正文 label，用于朗读）
function ui_page()
  if mode=="reader" then return ui.get(W.r_body) end
  return ui_dump()
end

function ui_save_page()
  local s=ui_page()
  local f=io.open("/tmp/ui_page.txt","w"); if f then f:write(s.."\n"); f:close() end
  return s
end

-- 当前屏可见文本（直接读回 label，无需 OCR）
function ui_dump()
  local out={}
  local function add(o) if o then local t=ui.get(o); if t and #t>0 then out[#out+1]=t end end end
  if mode=="reader" then add(W.r_title); add(W.r_body); add(W.r_page); add(W.r_hint)
  else add(W.l_title); add(W.l_body); add(W.l_hint) end
  return table.concat(out,"\n")
end

function ui_save_text()
  local s=ui_dump()
  local f=io.open("/tmp/ui_text.txt","w"); if f then f:write(s.."\n"); f:close() end
  return s
end

-- ===== 文本指令（语音 / 远程 / 无障碍）：cmd("下一页")、cmd("读异类") =====
local function nospace(x) return (x:gsub("[%s\r\n]+","")) end
local function strip_pre(x, list)
  local ch=true
  while ch do ch=false
    for _,p in ipairs(list) do
      if #x>=#p and x:sub(1,#p)==p then x=x:sub(#p+1); ch=true; break end
    end
  end
  return x
end
local function strip_suf(x, list)
  local ch=true
  while ch do ch=false
    for _,p in ipairs(list) do
      if #x>=#p and x:sub(#x-#p+1)==p then x=x:sub(1,#x-#p); ch=true; break end
    end
  end
  return x
end

local function find_book(q)
  q = nospace(q)
  if q=="" then return nil end
  for _,n in ipairs(ls_books()) do
    local base = n:gsub("%.%w+$","")
    if n==q or base==q or n:find(q,1,true) or base:find(q,1,true) then return n end
  end
  return nil
end

local function cur_chapter()
  if #toc==0 then return nil end
  local ln=(page-1)*cur_lines+1; local idx=0
  for i,c in ipairs(toc) do if c.line<=ln then idx=i else break end end
  return idx
end

local function jump_chapter(arg)
  if #toc==0 then return false end
  local idx = tonumber(arg)
  if not idx then
    local q=nospace(tostring(arg))
    for i,c in ipairs(toc) do if c.title:find(q,1,true) then idx=i; break end end
  end
  if not idx or not toc[idx] then return false end
  tsel = math.max(1, math.min(#toc, idx)); toc_jump(); return true
end

function cmd(text)
  local s = tostring(text or "")
  local t = nospace(s)
  local acted = "?"
  local function has(...) for _,w in ipairs{...} do if s:find(w,1,true) then return true end end return false end

  local pn = tonumber(t:match("第(%d+)页")) or tonumber(t:match("(%d+)页"))
  local cn = t:match("第(%d+)章")

  if pn then
    if mode~="reader" and last_book then open_book(last_book) end
    page = math.max(1, math.min(npages, pn)); pos[curname]=page; save_pos()
    screen("reader"); render(); acted="page:"..page
  elseif has("下一章") then
    local i=cur_chapter()
    if i and toc[i+1] then jump_chapter(i+1); acted="nextchapter" else acted="nextchapter:none" end
  elseif has("上一章","前一章") then
    local i=cur_chapter()
    if i and toc[i-1] then jump_chapter(i-1); acted="prevchapter" else acted="prevchapter:none" end
  elseif cn then
    if jump_chapter(cn) then acted="chapter:"..cn end
  elseif has("目录") then open_toc(); acted="toc"
  elseif has("书架","书库","首页") then shelf(); acted="shelf"
  elseif has("菜单") then open_menu(); acted="menu"
  elseif has("下一页","下页","往后","翻页") then on_key("nextpage"); acted="nextpage"
  elseif has("上一页","上页","往前","回看") then on_key("prevpage"); acted="prevpage"
  elseif has("快进","后十页","下十页") then on_key("down"); acted="forward10"
  elseif has("快退","前十页","上十页") then on_key("up"); acted="back10"
  elseif has("字号大","放大字号","大号","字大","调大") then
    while SIZES[ssize].name~="大" do set_size(1) end; acted="size:大"
  elseif has("字号小","缩小字号","小号","字小","调小") then
    while SIZES[ssize].name~="小" do set_size(1) end; acted="size:小"
  elseif has("字号中","中号","默认字号") then
    while SIZES[ssize].name~="中" do set_size(1) end; acted="size:中"
  elseif has("进度","读到哪","第几页") then
    acted="status"
  else
    local q = strip_pre(s, {"请帮我","请","打开","读一下","读一读","读","看","播放"})
    q = strip_suf(q, {"这本书","那本书","一书","书"})
    q = strip_pre(q, {" ","，",",","：",":","。","！","!","？","?"})
    q = strip_suf(q, {"。","！","!","？","?"})
    local bn = find_book(q) or find_book(t)
    if bn then open_book(bn); acted="open:"..bn end
  end

  ui.log("cmd ["..s.."] -> "..acted)
  ui_save_state()
  return ui_info()
end

load_pos(); initui()
os.execute("echo unlock > /proc/keypad")
os.execute("echo unlock > /proc/fiveway")
-- UI_START=shelf 时固定从书架开始（手机 kiosk 等场景），否则续读上次的书
if os.getenv("UI_START") ~= "shelf" and last_book and load_text(last_book) then
  open_book(last_book)
else
  shelf()
end
