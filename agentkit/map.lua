-- agentkit/map.lua — 应用控件映射（每个按钮/图标一个命名区域，固化后无需再探索）
-- 映射文件：agentkit/maps/<app>.lua，形如
--   return { window="微信", controls = { search_box={x,y,w,h}, ... } }
local x11 = require("agentkit.x11")
local M = {}

local MAPS_DIR = os.getenv("AGENTKIT_MAPS") or "/opt/my-agent/agentkit/maps"

local function serialize(def)
    local L = { "return {", string.format("  window = %q,", def.window or "") }
    if def.class then L[#L + 1] = string.format("  class = %q,", def.class) end
    L[#L + 1] = "  controls = {"
    local names = {}
    for k in pairs(def.controls or {}) do names[#names + 1] = k end
    table.sort(names)
    for _, k in ipairs(names) do
        local c = def.controls[k]
        local extra = ""
        if c.text then extra = extra .. string.format(", text=%q", c.text) end
        if c.icon then extra = extra .. string.format(", icon=%q", c.icon) end
        L[#L + 1] = string.format("    %s = { x=%d, y=%d, w=%d, h=%d%s },",
                                  k, c.x, c.y, c.w, c.h, extra)
    end
    L[#L + 1] = "  },"
    L[#L + 1] = "}"
    return table.concat(L, "\n") .. "\n"
end

local Map = {}
Map.__index = Map
M.Map = Map

function M.load(app)
    local path = MAPS_DIR .. "/" .. app .. ".lua"
    local chunk = loadfile(path)
    local def = chunk and chunk() or { window = app, controls = {} }
    return setmetatable({ app = app, def = def, path = path }, Map)
end

function Map:window(opts)
    opts = opts or { exact = true }
    return x11.window(self.def.window or self.app, opts)
end

function Map:ctrl(name) return self.def.controls[name] end

function Map:center(name)
    local c = self:ctrl(name)
    if not c then return nil end
    return { x = c.x + math.floor(c.w / 2), y = c.y + math.floor(c.h / 2) }
end

-- 按控件名点击（窗口相对区域中心）
function Map:click(name, win)
    win = win or self:window()
    if not win then return false, "no window" end
    local c = self:ctrl(name)
    if not c then return false, "no control: " .. name end
    win:click(c.x + math.floor(c.w / 2), c.y + math.floor(c.h / 2))
    return true
end

-- 对某控件区域做 OCR
function Map:ocr(name, win)
    win = win or self:window()
    local c = self:ctrl(name)
    if not c then return {} end
    return win:ocr({ c.x, c.y, c.w, c.h })
end

-- 点击控件并输入（自动切换输入法语言）
local function is_ascii(s) return not s:find("[\128-\255]") end
function Map:type(name, s, win, opts)
    opts = opts or {}
    self:click(name, win)
    os.execute("sleep 0.25")
    local lang = opts.lang or (is_ascii(s) and "en" or "zh")
    if lang == "en" then x11.ime_en() else x11.ime_zh() end
    os.execute("sleep 0.15")
    os.execute(("xdotool type --delay 40 %q"):format(s))
    x11.ime_restore()
end

-- 记录/更新一个控件（探索时调用），可 chain: map:learn("x",1,2,3,4):save()
function Map:learn(name, x, y, w, h, extra)
    local c = { x = x, y = y, w = w, h = h }
    if extra then for k, v in pairs(extra) do c[k] = v end end
    self.def.controls[name] = c
    return self
end

function Map:save()
    local f = assert(io.open(self.path, "w"))
    f:write(serialize(self.def))
    f:close()
    return self.path
end

return M
