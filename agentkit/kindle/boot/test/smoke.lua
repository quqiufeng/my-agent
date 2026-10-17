-- 冒烟测试：模拟人手动操作 + 文本指令（结果写 events 的 PASS/FAIL）
-- 用法：kui run smoke.lua
local pass, fail = 0, 0
local function ok(c, msg)
  if c then pass=pass+1; ui.log("PASS "..msg)
  else fail=fail+1; ui.log("FAIL "..msg) end
end
local function S() return ui_info() end
local function item() return S().item or "" end
local function menu_goto(word)
  for i=1,S().menu_n do
    if item():find(word,1,true) then return true end
    tap("down")
  end
  return item():find(word,1,true)~=nil
end

-- 记录测试前状态（结束后恢复，避免污染真实阅读进度）
local saved = ui_info()
local saved_book, saved_page, saved_size = saved.book, saved.page, saved.size

-- 书架：选到多页书《异类》
shelf()
ok(S().mode=="shelf", "进入书架")
ok(S().books>=1, "书架非空("..S().books.."本)")
for i=1,S().books do
  if item():find("异类",1,true) then break end
  tap("down")
end
ok(item():find("异类",1,true)~=nil, "选中《异类》")

-- 打开 + 翻页
tap("enter")
ok(S().mode=="reader", "中键打开书: "..S().book)
ok(S().npages>1, "多页书("..S().npages.."页)")
local p = S().page
tap("nextpage"); ok(S().page==math.min(S().npages,p+1), "下一页 "..p.."->"..S().page)
tap("prevpage"); ok(S().page==p, "上一页 ->"..S().page)
local p2 = S().page
tap("up");   ok(S().page==math.max(1,p2-10), "上翻10页 ->"..S().page)
local ua = S().page
tap("down"); ok(S().page==math.min(S().npages,ua+10), "下翻10页 ->"..S().page)

-- 菜单：按名称找「字号」
tap("enter"); ok(S().mode=="menu", "中键打开菜单")
local sz0 = S().size
ok(menu_goto("字号"), "菜单含字号项")
tap("enter"); ok(S().size~=sz0, "切换字号 "..sz0.."->"..S().size)
tap("back"); ok(S().mode=="reader", "菜单返回阅读")

-- 目录
tap("enter"); ok(S().mode=="menu", "再开菜单")
if S().toc_n>0 then
  if menu_goto("目录") then
    tap("enter"); ok(S().mode=="toc", "打开目录("..S().toc_n.."节)")
    if S().mode=="toc" then
      tap("down"); tap("enter")
      ok(S().mode=="reader", "目录跳转 -> 第"..S().page.."页")
    end
  end
end
tap("home"); ok(S().mode=="shelf", "Home 回书架")

-- 游戏：贪吃蛇（键盘/五向键 + 局部刷新）
tap("enter"); ok(S().mode=="reader", "打开书(准备进菜单)")
tap("enter"); ok(S().mode=="menu", "打开菜单(游戏)")
if menu_goto("游戏") then
  tap("enter"); ok(S().mode=="snake", "进入贪吃蛇")
  local i = snake_info()
  ok(i and i.len==3, "蛇初始长度 3")
  tap("up"); ok(snake_info().dy==-1, "转向(上)")
  tap("home"); ok(S().mode=="shelf", "退出游戏")
end

-- 文本指令（语音 / 无障碍通道）
cmd("读异类"); ok(S().mode=="reader", "语音: 读异类 -> "..S().book)
local p3=S().page
cmd("下一页"); ok(S().page==math.min(S().npages,p3+1), "语音: 下一页 "..p3.."->"..S().page)
cmd("上一页"); ok(S().page==p3, "语音: 上一页 ->"..S().page)
cmd("跳到第3页"); ok(S().page==math.min(S().npages,3), "语音: 跳到第3页 ->"..S().page)
cmd("字号大"); ok(S().size=="大", "语音: 字号大")
cmd("字号中"); ok(S().size=="中", "语音: 字号中")
cmd("回到书架"); ok(S().mode=="shelf", "语音: 回书架")

-- 屏幕文本可读（免 OCR）
ui_save_text()
ok(#(ui_dump())>0, "可读屏文本("..#(ui_dump()).." bytes)")

-- 恢复测试前状态
if saved_book and saved_book~="" then cmd("读"..saved_book) end
if saved_size then cmd("字号"..saved_size) end
if saved_page then cmd("跳到第"..saved_page.."页") end
ui.log("已恢复: "..tostring(saved_book).." 第"..tostring(saved_page).."页 "..tostring(saved_size))

ui.log(string.format("SMOKE DONE pass=%d fail=%d", pass, fail))
