# Lua 功能开发指南（kindle lvgui）

界面逻辑全在 Lua：`lvgui`（C）只负责 LVGL 渲染、字体、按键与管道，启动时 `dofile /mnt/us/ui/init.lua`。
**改界面/加功能只改这里的 .lua，不用重编 C。**

---

## 1. 运行模型

```
lvgui 启动
  └─ dofile /mnt/us/ui/init.lua        -- 你的脚本（只执行一次）
  └─ 主循环:
       ├─ 读 /tmp/ui.cmd (FIFO)      -- 每行 = 一条 Lua 语句，立即执行
       ├─ 有改动 → lv_refr_now()      -- 重绘到内存灰度缓冲
       ├─ 有变化(dirty)时，间隔≥1500ms → 写 /tmp/ui_frame.png 并调 eips  -- 推屏（空闲不刷）
       └─ 按键 → on_code(raw) / on_key(name)
```

要点：
- **UI 改动最多 1.5s 后出现在屏上**（`REFRESH_MS=1500`）；**只推脏页**，空闲不刷屏（省电、少残影）。
  需要立即出图用 `ui.flush()`（`kui shot` 已内置）。
- 屏幕是 **824×1200 竖屏坐标系**（左上角 0,0）。
- 所有控件都挂在当前活动屏上；`ui.clear()` 会全部清掉。
- 日志写 `/mnt/us/ui/events`（`log/click/open/luaerr`）。

---

## 2. API 一览

对象都是 lightuserdata 句柄，存进 Lua table 复用即可。

| API | 说明 |
|---|---|
| `ui.text(x, y, str, size)` | 建文本，返回句柄。`size` 可为像素数或 `ui.font()` 句柄（默认 26） |
| `ui.label(str, size)` | 同上但不定位置（默认 24） |
| `ui.title(str)` | 顶部居中标题（字号 32），全局唯一 |
| `ui.set(obj, str)` | 改文本（支持 `\n` 多行，一个 label 即整页正文） |
| `ui.pos(obj, x, y)` | 移动 |
| `ui.size(obj, w, h)` | 改尺寸 |
| `ui.align(obj, ui.ALIGN_*, dx, dy)` | 对齐（`ALIGN_CENTER/TOP_MID/BOTTOM_MID/LEFT_MID/RIGHT_MID`） |
| `ui.color(obj, 0xRRGGBB)` | 文字颜色 |
| `ui.show(obj, bool)` | 显示/隐藏（**多屏切换靠它，不要反复 clear 重建**） |
| `ui.style(obj, line_space, letter_space)` | 行距/字距 |
| `ui.hr(x, y, w)` | 1px 分隔线，返回句柄 |
| `ui.font(px)` | 取指定像素字号句柄（内部按字号缓存） |
| `ui.setfont(obj, size)` | 改已有对象的字号（改字号后必须重排，见 §6） |
| `ui.measure(str, size)` | 返回该串在指定字号下的 `宽, 高`（像素），用于精确排版 |
| `ui.zoom(obj, z)` | 缩放（256=1x，实验性，墨水屏上优先用 `setfont`） |
| `ui.button(str, cb)` | 360×110 按钮，点击回调 `cb(str)` |
| `ui.list(array, cb)` | 列表，每项点击回调 `cb(item)` |
| `ui.clear()` | 清屏并重建按键组 |
| `ui.get(obj)` | 读回 label 文本（agent 断言用） |
| `ui.log(msg)` | 写日志到 `events` |

常量：`ui.ALIGN_*`。

---

## 3. 字号与度量

`size` 就是**真实像素字号**（FreeType 精确加载，不再四舍五入）：

```lua
local body = ui.text(46, 194, "", 26)      -- 26px 正文
local w, h = ui.measure("汉", 26)          -- w=26, h=33（单字宽、行高）
```

- 单字宽 ≈ 字号；行高 ≈ 字号 × 1.26（中文字体）。
- 可同时用多个字号（内部缓存，最多 16 种）。

---

## 4. 按键

C 优先调用 **`on_code(rawcode)`**（原始扫描码）；**只有没定义 `on_code` 时才回退 `on_key(name)`**。

实机扫描码（同码只走一个分支）：

| 键 | code | 来源 |
|---|---|---|
| Home | 98 | event0 |
| Back | 91 | event0 |
| Menu | 139 | event0 |
| 上一页 | 109 | event0 |
| 下一页 | 124 | event0 |
| 上 / 下 | 122 / 123 | event1（五向键） |
| 中键 | 92 | event1 |
| 左 / 右 | 105 / 106 | event1 |

推荐写法（与 `init.lua` 一致）：

```lua
local CODE = {[98]="home",[91]="back",[139]="menu",[109]="prevpage",[124]="nextpage",
              [122]="up",[123]="down",[92]="enter",[105]="left",[106]="right"}
function on_code(c) local k=CODE[c]; if k then on_key(k) end end
```

> 键默认被内核锁住，脚本启动时要 `echo unlock > /proc/keypad`、`echo unlock > /proc/fiveway`
> （`init.lua` 已做）。不需要额外的 keyd 进程。

**顶部 lock 开关**：拨动时驱动会锁住 keypad/fiveway/accelerometer，lvgui 轮询
`/proc/keypad` 并回调 Lua `on_lock(true|false)`。锁定显示 `/mnt/us/ui/lock.gray`
（824×1200 8 位灰度原始图，缺失则回退文字），解锁自动恢复原界面。

换锁屏图：

```bash
python3 boot/lock/make_lock.py 原图.png            # -> lock.gray
scp -O boot/lock/lock.gray kindle:/mnt/us/ui/lock.gray
./kui lock on    # 测试；./kui lock off  解锁
```

---

## 5. 推荐的写法（常驻控件 + show/hide）

`init.lua` 的模式：**启动时把所有屏的控件建好**，切屏只 `show/hide`，翻页只 `ui.set`。
好处：不闪烁、不重建、内存稳定。

```lua
local W = {}
local function initui()
  W.r_body  = ui.text(46,194,"",26);  ui.style(W.r_body,14,1)
  W.l_title = ui.text(0,0,"",34);     ui.align(W.l_title, ui.ALIGN_TOP_MID,0,44)
end
local function screen(which)
  ui.show(W.r_body,  which=="reader")
  ui.show(W.l_title, which=="list")
end
```

正文用一个 label 装整页，行间用 `\n`：

```lua
ui.set(W.r_body, table.concat(page_lines, "\n"))
```

---

## 6. 排版与分页（切字号必须重排）

换字号时**既要改字体，又要重新分页**，否则会出现「字变大但每行还是旧字数」的右侧大留白。

```lua
local AREA_W, AREA_H = 732, 926        -- 正文可用区（按控件位置自算）
local function metrics(fs, ls)
  local cw    = ui.measure("汉", fs)       -- 单字宽
  local _, lh = ui.measure("汉", fs)       -- 行高
  local maxw  = math.floor(AREA_W/(cw+1))*2  -- 每行半角单位（汉字=2）
  local lines = math.floor(AREA_H/(lh+ls))
  return maxw, lines
end

local function repaginate(txt, fs, ls)
  ui.setfont(W.r_body, fs)                  -- 1) 改字体
  ui.style(W.r_body, ls, 1)                 -- 2) 改行距
  local maxw, lines = metrics(fs, ls)       -- 3) 按真实度量算每行字数
  -- ... 重新折行/分页 ...
end
```

折行工具 `wrap()` 与避头尾标点逻辑见 `init.lua`。

`ui.measure` 也适合做「宽度自适应」：例如标题过长时自动降字号。

---

## 7. 调试

```bash
K=~/opt/arm-linux-musleabi-cross        # 仅示意

# 1) 往 UI 里塞一条 Lua（FIFO，逐行执行）
ssh kindle 'echo "ui.log(\"hello\")" > /tmp/ui.cmd'

# 2) 模拟按键（走和硬件一样的 Lua 回调路径）
ssh kindle 'echo "on_code(92)" > /tmp/ui.cmd'      # 中键
ssh kindle 'echo "on_code(124)" > /tmp/ui.cmd'     # 下一页

# 3) 看日志（含 luaerr 报错）
ssh kindle 'tail -20 /mnt/us/ui/events'

# 4) 抓当前屏（最可靠，比读 fb 强）
scp -O kindle:/tmp/ui_frame.png .        # 824x1200 正向灰度 PNG

# 5) 重启 UI
ssh kindle 'killall lvgui; /sbin/start-stop-daemon -S -b -x /mnt/us/lvgui'
```

注意：FIFO 每行是**一条** Lua 语句，不能直接贴多行函数；要执行大段代码就用文件 + `dofile`：

```bash
ssh kindle 'echo "dofile(\"/mnt/us/ui/t.lua\")" > /tmp/ui.cmd'
```

热重载 `init.lua`（旧控件不会自动消失，建议先 `ui.clear()`）：

```bash
ssh kindle 'echo "ui.clear() dofile(\"/mnt/us/ui/init.lua\")" > /tmp/ui.cmd'
```
正式验证仍建议直接重启 `lvgui`。

---

## 8. agent 自动化与测试（模拟人手动操作）

### 设备侧 Lua 接口（`init.lua` 已内置）

| 接口 | 说明 |
|---|---|
| `ui_info()` | 状态 table：`mode/page/npages/pct/size/book/books/sel/menu_n/menu_sel/toc_n/toc_sel/item` |
| `ui_state()` | 同上的 JSON 字符串 |
| `ui_save_state()` | 写 `/tmp/ui_state.json`（每次渲染后自动刷新） |
| `tap(name\|code)` | 模拟一次按键（`"nextpage"` 或 `124`），返回最新 `ui_info()` |
| `ui_dump()` | 当前屏可见文本（直接读 label，**不需要 OCR**） |
| `ui_save_text()` | 写 `/tmp/ui_text.txt` |
| `ui.get(obj)` | 读任意 label 文本（C 提供） |
| `ui.flush()` | 同步重绘并推屏（截图前调用，保证是最新帧） |
| `ui.seq()` | 命令序号（供外部同步，见 `kui`） |
| `ui.talign(obj, n)` | 文本对齐（0=左 / 1=中 / 2=右） |
| `ui.overlay(path\|nil)` | 设置/清除全屏灰度覆盖图（824×1200 8 位原始数据，用于锁屏图） |

按键名：`home back menu prevpage nextpage up down left right enter`

### 主机侧 CLI：`boot/test/kui`

```bash
cd boot/test
./kui state              # {"mode":"reader","page":9,...}
./kui tap nextpage       # 按键并返回新状态
./kui dump               # 当前屏文本
./kui shot /tmp/a.png    # 抓帧（视觉回归）
./kui run smoke.lua      # 跑测试脚本，输出 PASS/FAIL
./kui eval 'ui.log("hi")'
./kui restart
./kui say "读异类"         # 文本指令（语音/无障碍）
```

设备侧原生文本通道（不经 Lua 包装，ASR 直接可用）：

```bash
ssh kindle 'echo "下一页" > /tmp/ui_say'
```

**完整的「截图 → AI 看界面 → 自主修复 → 回归」闭环流程见
[`../test/README.md`](../test/README.md)。**

### 写测试

```lua
shelf()
ok(ui_info().mode=="shelf", "进入书架")
local p = ui_info().page
tap("nextpage")
ok(ui_info().page==p+1, "翻页")
ui.log("SMOKE DONE pass=..fail=..")
```

`boot/test/smoke.lua` 覆盖：书架 / 开书 / 翻页 / ±10 页 / 菜单 / 字号 / 目录跳转 / Home / 读屏，
当前结果 **pass=15 fail=0**。

> 测试会真实翻页并写进度 `pos.lua`。

---

## 9. 部署与回滚

```bash
# 应用层（只改 Lua）
scp -O boot/lua/init.lua kindle:/mnt/us/ui/init.lua
ssh kindle 'killall lvgui; /sbin/start-stop-daemon -S -b -x /mnt/us/lvgui'

# 回滚：把旧 .lua 覆盖回去再重启即可（无需重编）
```

C 层改动见 `../src/`（`sh build.sh` 产出 `lvgui`，scp 到 `/mnt/us/lvgui`）。

---

## 10. 新增一个功能的完整示例

以「新增统计页」为例，在 `init.lua` 上四步：

```lua
-- (1) 常驻控件
local S = {}
local function init_stat()
  S.title = ui.text(0,0,"阅读统计",30); ui.align(S.title, ui.ALIGN_TOP_MID,0,44)
  S.body  = ui.text(46,150,"",24);      ui.style(S.body,16,1)
  S.hint  = ui.text(46,1146,"← 返回",17); ui.color(S.hint,0xaaaaaa)
end

-- (2) 显示/隐藏
local function show_stat(on)
  ui.show(S.title,on); ui.show(S.body,on); ui.show(S.hint,on)
end

-- (3) 渲染
local function render_stat()
  local t={}
  for _,n in ipairs(books) do t[#t+1]=n end
  ui.set(S.body, "共 "..#books.." 本\n\n"..table.concat(t,"\n"))
end
```

```lua
-- (4) 菜单里加一项，并在 on_key 的 menu 分支处理
-- open_menu():   mitems[#mitems+1]={t="统计", a="stat"}
-- menu 分支:     elseif a=="stat" then
--                  screen("none"); show_stat(true); render_stat(); mode="stat"
-- 按键分支:      elseif mode=="stat" then
--                  if k=="back" or k=="left" or k=="home" then
--                    show_stat(false); open_menu()
--                  end
```

---

## 11. 常见坑

1. **改字号不改字体** → 排版/留白错乱（见 §6）。
2. **每页 `ui.clear()` 重建** → 闪烁、句柄失效；用常驻控件 + `show`。
3. **多行代码塞 FIFO** → 只有第一行生效；用 `dofile`。
4. **报错看不到** → 查 `events` 里的 `luaerr`。
5. **按键没反应** → 确认 `/proc/keypad`、`/proc/fiveway` 已 `unlock`。
6. **`ui.title` 只有一个**（全局 `g_title`），多次调用是改文本不是新建。
7. **`on_code` 一旦定义，`on_key` 不再被调用**。
8. `ui.zoom` 是位图缩放，墨水屏上不如直接换字号清晰。
9. 推屏只在画面有变化时发生；如果你直接改了 `g_gray` 或外挂逻辑却没触发重绘，记得 `ui.flush()`。
