-- 贪吃蛇（电纸书版）：对象化渲染 + 局部刷新
-- 墙/食物/蛇身各自是独立 label，每步只移动变化的对象，避免整块文本重排。
-- 对外: snake_start/snake_key/snake_tick/snake_hide/snake_state/snake_info
--       snake_auto/snake_manual/snake_setdir/snake_step
local SW, SH = 36, 35          -- 总格数（含围墙）
local CELL, GH = 20, 25        -- 格宽=字号, 行高
local FX, FY = 46, 150         -- 棋盘左上角像素
local BESTFILE = "/mnt/us/ui/snake_best"

local G = { interval = 200, seg_n = 0, moves = 0 }
local objs = { seg = {} }
local step   -- 前向声明

local function read_best()
  local f = io.open(BESTFILE, "r")
  if f then local s = f:read("*n"); f:close(); return tonumber(s) or 0 end
  return 0
end
local function save_best()
  local f = io.open(BESTFILE, "w"); if f then f:write(G.best or 0); f:close() end
end

local function ensure_ui()
  if objs.ready then return end
  objs.title = ui.text(0, 0, "贪吃蛇", 32); ui.align(objs.title, ui.ALIGN_TOP_MID, 0, 14)
  objs.score = ui.text(46, 104, "", 17); ui.color(objs.score, 0x777777)
  objs.hint  = ui.text(46, 1146, "↑↓←→/WASD 转向 · 中键/空格 暂停 · 1/2/3 速度 · R 重开 · Home 退出", 17)
  ui.color(objs.hint, 0xaaaaaa)
  local top  = string.rep("■", SW)
  local side = string.rep("■\n", SH - 1) .. "■"
  objs.wt = ui.text(FX, FY, top, CELL);                          ui.style(objs.wt, 0, 0)
  objs.wb = ui.text(FX, FY + (SH-1)*GH, top, CELL);              ui.style(objs.wb, 0, 0)
  objs.wl = ui.text(FX, FY, side, CELL);                         ui.style(objs.wl, 0, 0)
  objs.wr = ui.text(FX + (SW-1)*CELL, FY, side, CELL);           ui.style(objs.wr, 0, 0)
  objs.food = ui.text(FX, FY, "●", CELL);                        ui.style(objs.food, 0, 0)
  objs.ready = true
end

local function px(x) return FX + (x-1)*CELL end
local function py(y) return FY + (y-1)*GH end

local function seg_obj(i)
  local o = objs.seg[i]
  if not o then
    o = ui.text(FX, FY, "■", CELL); ui.style(o, 0, 0)
    objs.seg[i] = o
  end
  return o
end

local function render_snake()
  for i, p in ipairs(G.snake) do
    local o = seg_obj(i)
    ui.pos(o, px(p.x), py(p.y))
    ui.show(o, true)
  end
  for i = #G.snake + 1, G.seg_n do ui.show(objs.seg[i], false) end
  if #G.snake > G.seg_n then G.seg_n = #G.snake end
end

local function speed_name()
  if G.interval <= 300 then return "快" elseif G.interval >= 600 then return "慢" else return "中" end
end

local function push_state()
  local f = io.open("/tmp/snake_state.json", "w")
  if f then f:write(snake_state() .. "\n"); f:close() end
end

local function score_line()
  local st = G.over and "结束(中键重开)" or (G.paused and "暂停" or (G.manual and "手动" or "进行中"))
  return string.format("得分 %d   最高 %d   速度 %s   %s", G.score, G.best, speed_name(), st)
end

local function draw(rect_only)
  ensure_ui()
  render_snake()
  if G.food then ui.pos(objs.food, px(G.food.x), py(G.food.y)); ui.show(objs.food, true) end
  ui.set(objs.score, score_line())
  if rect_only and G.dirty and #G.dirty > 0 then
    -- 只推变动过的格子（走过的格子各推一次，位置精确）
    for _, c in ipairs(G.dirty) do
      ui.flushrect(px(c.x) - 2, py(c.y) - 2, CELL + 4, GH + 4)
    end
  else
    ui.flush()
  end
  push_state()
end

function snake_hide()
  for _, o in pairs(objs) do
    if type(o) == "userdata" then ui.show(o, false) end
  end
  for _, o in ipairs(objs.seg) do ui.show(o, false) end
end

local function occupied(x, y)
  for _, p in ipairs(G.snake) do if p.x == x and p.y == y then return true end end
  return false
end

local function place_food()
  for _ = 1, 500 do
    local x, y = math.random(2, SW-1), math.random(2, SH-1)
    if not occupied(x, y) then G.food = { x = x, y = y }; return end
  end
  G.food = { x = 2, y = 2 }
end

local function reset()
  math.randomseed(os.time())
  local cx, cy = math.floor(SW/2), math.floor(SH/2)
  G.snake = { {x=cx,y=cy}, {x=cx-1,y=cy}, {x=cx-2,y=cy} }
  G.dir = { x = 1, y = 0 }
  G.score, G.over, G.paused, G.acc, G.moves = 0, false, false, 0, 0
  G.best = read_best()
  G.dirty = nil
  place_food()
end

function snake_start()
  reset()
  ensure_ui()
  for _, o in pairs(objs) do
    if type(o) == "userdata" then ui.show(o, true) end
  end
  for _, o in ipairs(objs.seg) do ui.show(o, true) end
  draw(false)
end

function snake_body()
  local t = {}
  for i, p in ipairs(G.snake) do t[i] = { x = p.x, y = p.y } end
  return t
end

function snake_info()
  return { score = G.score, best = G.best, over = G.over, paused = G.paused,
           len = #G.snake, interval = G.interval,
           hx = G.snake[1].x, hy = G.snake[1].y,
           fx = G.food and G.food.x or 0, fy = G.food and G.food.y or 0,
           w = SW, h = SH, dx = G.dir.x, dy = G.dir.y, body = snake_body() }
end

local function body_json()
  local t = {}
  for i, p in ipairs(G.snake) do t[i] = string.format("[%d,%d]", p.x, p.y) end
  return "[" .. table.concat(t, ",") .. "]"
end

function snake_state()
  local i = snake_info()
  return string.format('{"score":%d,"best":%d,"over":%s,"paused":%s,"len":%d,"interval":%d,"head":[%d,%d],"dir":[%d,%d],"food":[%d,%d],"size":[%d,%d],"moves":%d,"body":%s}',
    i.score, i.best, tostring(i.over), tostring(i.paused), i.len, i.interval,
    i.hx, i.hy, i.dx, i.dy, i.fx, i.fy, i.w, i.h, G.moves, body_json())
end

local function die()
  G.over = true
  if G.score > G.best then G.best = G.score; save_best() end
end

step = function()
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
    dirty[#dirty+1] = { x = G.food.x, y = G.food.y }
    G.score = G.score + 10
    if G.score > G.best then G.best = G.score; save_best() end
    place_food()
    dirty[#dirty+1] = { x = G.food.x, y = G.food.y }
  else
    local t = table.remove(G.snake)
    dirty[#dirty+1] = { x = t.x, y = t.y }
  end
  G.dirty, G.ate = dirty, eat
  G.moves = G.moves + 1
  return true
end

function snake_tick(dt)
  if G.over or G.paused or G.manual then return false end
  G.acc = G.acc + (dt or 100)
  if G.acc >= G.interval then
    G.acc = 0
    if snake_ai_prestep then snake_ai_prestep() end
    if step() then draw(not G.ate); G.dirty = nil; G.ate = false end
  end
  return false
end

local function norm(k)
  if type(k) ~= "number" then return k end
  local t = {
    [122]="up", [123]="down", [105]="left", [106]="right",
    [98]="home", [91]="back", [92]="enter", [139]="menu",
    [17]="up", [31]="down", [30]="left", [32]="right",
    [57]="space", [19]="r",
    [2]="1", [3]="2", [4]="3",
  }
  return t[k] or tostring(k)
end

function snake_key(raw)
  if not objs.ready then return nil end
  local k = norm(raw)
  if k == "home" or k == "back" then
    if G.score > G.best then G.best = G.score; save_best() end
    snake_hide(); return "exit"
  elseif k == "space" or k == "enter" or k == "menu" then
    if G.over then reset() else G.paused = not G.paused end
    draw(false)
  elseif k == "r" then reset(); draw(false)
  elseif k == "up"    then if G.dir.y == 0 then G.dir = { x = 0, y = -1 } end
  elseif k == "down"  then if G.dir.y == 0 then G.dir = { x = 0, y = 1 } end
  elseif k == "left"  then if G.dir.x == 0 then G.dir = { x = -1, y = 0 } end
  elseif k == "right" then if G.dir.x == 0 then G.dir = { x = 1, y = 0 } end
  elseif k == "1" then G.interval = 400; draw(false)
  elseif k == "2" then G.interval = 250; draw(false)
  elseif k == "3" then G.interval = 150; draw(false)
  else ui.log("snake key? "..tostring(raw)) end
  return nil
end

-- ===== agent 手动步进 =====
function snake_manual(on)
  G.manual = on and true or false
  if on then G.paused = false end
  draw(false)
  return G.manual
end
function snake_setdir(dx, dy)
  if not (dx == -G.dir.x and dy == -G.dir.y and #G.snake > 1) then
    G.dir = { x = dx, y = dy }
  end
end
function snake_step()
  if G.over then return false end
  local ok = step()
  if ok then draw(not G.ate); G.dirty = nil; G.ate = false end
  return ok
end

-- ===== 自动玩 =====
local DIRS = { {1,0}, {-1,0}, {0,1}, {0,-1} }

local function free_cell(x, y, occ)
  return x >= 2 and x <= SW-1 and y >= 2 and y <= SH-1 and not occ[y*SW+x]
end
local function area_of(sx, sy, occ)
  local seen = { [sy*SW+sx] = true }; local st = { {sx,sy} }; local n = 0
  while #st > 0 do
    local c = table.remove(st); n = n + 1
    for _, d in ipairs(DIRS) do
      local nx, ny = c[1]+d[1], c[2]+d[2]
      if free_cell(nx, ny, occ) and not seen[ny*SW+nx] then
        seen[ny*SW+nx] = true; st[#st+1] = {nx, ny}
      end
    end
  end
  return n
end
local function next_step_to_food(occ, h)
  local prev = {}; local seen = { [h.y*SW+h.x] = true }
  local q = { {h.x, h.y} }; local qi = 1
  while qi <= #q do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    if x == G.food.x and y == G.food.y then
      local cx, cy = x, y
      while true do
        local p = prev[cy*SW+cx]
        if not p then return nil end
        if p.x == h.x and p.y == h.y then return { x = cx - h.x, y = cy - h.y } end
        cx, cy = p.x, p.y
      end
    end
    for _, d in ipairs(DIRS) do
      local nx, ny = x+d[1], y+d[2]
      if free_cell(nx, ny, occ) and not seen[ny*SW+nx] then
        seen[ny*SW+nx] = true; prev[ny*SW+nx] = { x = x, y = y }; q[#q+1] = { nx, ny }
      end
    end
  end
  return nil
end

function snake_auto(on)
  G.auto = on and true or false
  if G.auto then G.paused = false; G.manual = false end
  draw(false)
  return G.auto
end

function snake_ai_prestep()
  if not G.auto or G.over or G.paused then return end
  local occ = {}
  for i, p in ipairs(G.snake) do if i < #G.snake then occ[p.y*SW+p.x] = true end end
  local h = G.snake[1]
  local d = next_step_to_food(occ, h)
  if not d then
    local best, best_n = nil, -1
    for _, dd in ipairs(DIRS) do
      local nx, ny = h.x+dd[1], h.y+dd[2]
      if free_cell(nx, ny, occ) then
        local n = area_of(nx, ny, occ)
        if dd.x == G.dir.x and dd.y == G.dir.y then n = n + 2 end
        if n > best_n then best_n, best = n, dd end
      end
    end
    d = best
  end
  if d and not (d.x == -G.dir.x and d.y == -G.dir.y and #G.snake > 1) then G.dir = d end
end
