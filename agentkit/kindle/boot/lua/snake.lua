-- 贪吃蛇（电纸书版）：全角字符网格 + 局部刷新，回合推进
-- 由 init.lua 载入；对外: snake_start/snake_key/snake_tick/snake_hide/snake_state/snake_info
local SW, SH = 36, 35          -- 总格数（含围墙）
local CELL   = 20              -- 字号 = 单格宽
local FX, FY = 46, 150         -- 棋盘左上角像素
local GH     = 25              -- 行高（fs20 实测）
local BESTFILE = "/mnt/us/ui/snake_best"

local G = {}
local objs = {}

local function read_best()
  local f = io.open(BESTFILE, "r")
  if f then local s = f:read("*n"); f:close(); return tonumber(s) or 0 end
  return 0
end
local function save_best()
  local f = io.open(BESTFILE, "w")
  if f then f:write(G.best or 0); f:close() end
end

local function occupied(x, y)
  for _, p in ipairs(G.snake) do if p.x == x and p.y == y then return true end end
  return false
end

local function place_food()
  for _ = 1, 500 do
    local x = math.random(2, SW - 1)
    local y = math.random(2, SH - 1)
    if not occupied(x, y) then G.food = { x = x, y = y }; return end
  end
  G.food = { x = 2, y = 2 }
end

local function reset()
  math.randomseed(os.time())
  local cx, cy = math.floor(SW / 2), math.floor(SH / 2)
  G.snake = { { x = cx, y = cy }, { x = cx - 1, y = cy }, { x = cx - 2, y = cy } }
  G.dir = { x = 1, y = 0 }
  G.score, G.over, G.paused, G.acc = 0, false, false, 0
  G.best = read_best()
  place_food()
end

local function ensure_ui()
  if objs.field then return end
  objs.title = ui.text(0, 0, "贪吃蛇", 32)
  ui.align(objs.title, ui.ALIGN_TOP_MID, 0, 14)
  objs.score = ui.text(46, 104, "", 17)
  ui.color(objs.score, 0x777777)
  objs.field = ui.text(46, 150, "", CELL)
  ui.style(objs.field, 0, 0)
  objs.hint = ui.text(46, 1146, "↑↓←→ 转向 · 中键 暂停 · 1/2/3 速度 · Home 退出", 17)
  ui.color(objs.hint, 0xaaaaaa)
end

local function build()
  local grid = {}
  for y = 1, SH do
    grid[y] = {}
    for x = 1, SW do grid[y][x] = "□" end
  end
  for x = 1, SW do grid[1][x] = "■"; grid[SH][x] = "■" end
  for y = 1, SH do grid[y][1] = "■"; grid[y][SW] = "■" end
  for _, p in ipairs(G.snake) do grid[p.y][p.x] = "■" end
  if G.food then grid[G.food.y][G.food.x] = "●" end
  local rows = {}
  for y = 1, SH do rows[y] = table.concat(grid[y]) end
  return table.concat(rows, "\n")
end

local function speed_name()
  if G.interval <= 300 then return "快" elseif G.interval >= 600 then return "慢" else return "中" end
end

local function draw(rect_only)
  ensure_ui()
  ui.set(objs.field, build())
  local st = G.over and "结束(中键重开)" or (G.paused and "暂停" or "进行中")
  ui.set(objs.score, string.format("得分 %d   最高 %d   速度 %s   %s", G.score, G.best, speed_name(), st))
  if rect_only and G.dirty and #G.dirty > 0 then
    -- 只推变化的格子（局部刷新，快很多）
    local x1, y1, x2, y2 = 1e9, 1e9, -1, -1
    for _, c in ipairs(G.dirty) do
      local px, py = FX + (c.x - 1) * CELL, FY + (c.y - 1) * GH
      if px < x1 then x1 = px end
      if py < y1 then y1 = py end
      if px + CELL > x2 then x2 = px + CELL end
      if py + GH   > y2 then y2 = py + GH end
    end
    ui.flushrect(x1 - 2, y1 - 2, (x2 - x1) + 4, (y2 - y1) + 4)
  else
    ui.flush()
  end
end

function snake_hide()
  for _, o in pairs(objs) do ui.show(o, false) end
end

function snake_start()
  reset()
  ensure_ui()
  for _, o in pairs(objs) do ui.show(o, true) end
  draw()
end

function snake_info()
  return { score = G.score, best = G.best, over = G.over, paused = G.paused,
           len = #G.snake, interval = G.interval,
           hx = G.snake[1].x, hy = G.snake[1].y,
           fx = G.food and G.food.x or 0, fy = G.food and G.food.y or 0,
           w = SW, h = SH, dx = G.dir.x, dy = G.dir.y }
end

function snake_state()
  local i = snake_info()
  return string.format('{"score":%d,"best":%d,"over":%s,"paused":%s,"len":%d,"interval":%d,"head":[%d,%d],"dir":[%d,%d],"food":[%d,%d],"size":[%d,%d]}',
    i.score, i.best, tostring(i.over), tostring(i.paused), i.len, i.interval,
    i.hx, i.hy, i.dx, i.dy, i.fx, i.fy, i.w, i.h)
end

local function die()
  G.over = true
  if G.score > G.best then G.best = G.score; save_best() end
end

local function step()
  if G.over or G.paused then return false end
  local h = G.snake[1]
  local nx, ny = h.x + G.dir.x, h.y + G.dir.y
  if nx <= 1 or nx >= SW or ny <= 1 or ny >= SH then die(); return true end
  for i = 1, #G.snake - 1 do
    local p = G.snake[i]
    if p.x == nx and p.y == ny then die(); return true end
  end
  local eat = (G.food and nx == G.food.x and ny == G.food.y)
  table.insert(G.snake, 1, { x = nx, y = ny })
  local dirty = { { x = nx, y = ny } }
  if eat then
    dirty[#dirty + 1] = { x = G.food.x, y = G.food.y }
    G.score = G.score + 10
    if G.score > G.best then G.best = G.score; save_best() end
    place_food()
    dirty[#dirty + 1] = { x = G.food.x, y = G.food.y }
  else
    local t = table.remove(G.snake)
    dirty[#dirty + 1] = { x = t.x, y = t.y }
  end
  G.dirty = dirty
  G.ate = eat
  return true
end

function snake_tick(dt)
  if G.over or G.paused then return false end
  G.acc = G.acc + (dt or 100)
  if G.acc >= G.interval then
    G.acc = 0
    if step() then
      draw(not G.ate)   -- 吃到食物时分数变了，走全刷
      G.dirty = nil; G.ate = false
    end
  end
  return false
end

-- 原始扫描码 → 游戏动作（五向键 + 键盘都支持）
local function norm(k)
  if type(k) ~= "number" then return k end
  local t = {
    [122]="up", [123]="down", [105]="left", [106]="right",
    [98]="home", [91]="back", [92]="enter", [139]="menu",
    [17]="up", [31]="down", [30]="left", [32]="right",   -- W S A D
    [57]="space", [19]="r",                              -- Space / R
    [2]="1", [3]="2", [4]="3",                           -- 1/2/3 速度
  }
  return t[k] or tostring(k)
end

-- 返回 "exit" 表示退出游戏
function snake_key(raw)
  if not objs.field then return nil end
  local k = norm(raw)
  if k == "home" or k == "back" then
    if G.score > G.best then G.best = G.score; save_best() end
    snake_hide()
    return "exit"
  elseif k == "space" then
    if G.over then reset() else G.paused = not G.paused end
    draw()
  elseif k == "r" then
    reset(); draw()
  elseif k == "enter" or k == "menu" then
    if G.over then reset() else G.paused = not G.paused end
    draw()
  elseif k == "up"    then if G.dir.y == 0 then G.dir = { x = 0, y = -1 } end
  elseif k == "down"  then if G.dir.y == 0 then G.dir = { x = 0, y = 1 } end
  elseif k == "left"  then if G.dir.x == 0 then G.dir = { x = -1, y = 0 } end
  elseif k == "right" then if G.dir.x == 0 then G.dir = { x = 1, y = 0 } end
  elseif k == "1" then G.interval = 600; draw()
  elseif k == "2" then G.interval = 450; draw()
  elseif k == "3" then G.interval = 300; draw()
  else
    ui.log("snake key? "..tostring(raw))   -- 未知键（便于补映射）
  end
  return nil
end

G.interval = 450
