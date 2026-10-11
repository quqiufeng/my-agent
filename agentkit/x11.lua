-- agentkit/x11.lua — 窗口定位（xdotool）/ 截屏与输入（libagentkit.so FFI）
-- 依赖：xdotool、libagentkit.so（agentkit/cpp 编译）
local ffi = require("ffi")

ffi.cdef[[
int    ak_capture(int x,int y,int w,int h,const char* out_png);
int    ak_move(int x,int y);
int    ak_click(int x,int y);
int    ak_button(int button);
int    ak_key(const char* combo);
int    ak_type(const char* utf8);
int    ak_match(const char* hay,const char* needle,double thr,int* cx,int* cy,double* score);
double ak_diff(const char* a,const char* b);
int    ak_find_window(const char* substr,int* x,int* y,int* w,int* h,unsigned long* wid);
int    ak_activate(unsigned long wid);
int    ak_center(unsigned long wid);
int    setenv(const char* name,const char* value,int overwrite);
]]

local LIB = os.getenv("AGENTKIT_LIB") or "/opt/my-agent/agentkit/lib/libagentkit.so"
local lib = ffi.load(LIB)

local M = { lib = lib }

-- ── shell ─────────────────────────────────────────────
local function sh(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return "" end
    local o = f:read("*a") or ""
    f:close()
    return o
end
M.sh = sh

local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- ── 输入法（IBus）：新应用默认中文，打字前切成目标语言 ──
local IME_EN = os.getenv("AGENTKIT_IME_EN") or "xkb:us::eng"
local IME_ZH = os.getenv("AGENTKIT_IME_ZH") or "libpinyin"
function M.ime_en() M.ensure_display(); sh("ibus engine " .. shq(IME_EN)) end
function M.ime_zh() M.ensure_display(); sh("ibus engine " .. shq(IME_ZH)) end

-- 通过剪贴板输入任意文本（绕过输入法，支持中英混合/符号）
function M.paste(text)
    M.ensure_display()
    local dir = os.getenv("AGENTKIT_TMP") or "/tmp/agentkit"
    os.execute("mkdir -p " .. dir)
    local tmp = dir .. "/clip.txt"
    local h = assert(io.open(tmp, "w")); h:write(text); h:close()
    -- 后台持有选区（重定向掉 stdout，避免 io.popen 挂起），随即 Ctrl+V
    os.execute(("xclip -selection clipboard < %s >/dev/null 2>&1 &"):format(shq(tmp)))
    os.execute("sleep 0.15")
    return sh("xdotool key --clearmodifiers ctrl+v")
end

-- ── 保证 DISPLAY / XAUTHORITY（从图形会话进程继承）─────
local _display_ready = false
function M.ensure_display()
    if _display_ready then return end
    _display_ready = true
    local d = os.getenv("DISPLAY")
    if d and d ~= "" then return end
    local pid = sh("pgrep -x pcmanfm-qt | head -1"):gsub("%s+", "")
    local xa = ""
    if pid ~= "" then
        local env = sh(("tr '\\0' '\\n' < /proc/%s/environ"):format(pid))
        xa = env:match("XAUTHORITY=([^\n]+)") or ""
    end
    ffi.C.setenv("DISPLAY", os.getenv("AGENTKIT_DISPLAY") or ":0", 1)
    if xa ~= "" then ffi.C.setenv("XAUTHORITY", xa, 1) end
end

-- ── xdotool 窗口检索（稳定）───────────────────────────
-- opts = { class=, exact=, all= }
function M.search(name, opts)
    M.ensure_display()
    opts = opts or {}
    local cmd = "xdotool search"
    if opts.class then
        cmd = cmd .. " --class " .. shq(opts.class)
    else
        cmd = cmd .. " --name " .. shq(name)
    end
    local ids = {}
    for id in sh(cmd):gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
    -- 精确标题过滤（避免子串命中多窗口，如浏览器标签）
    if opts.exact and not opts.class then
        local ex = {}
        for _, id in ipairs(ids) do
            local nm = sh(("xdotool getwindowname %d"):format(id)):gsub("\n$", "")
            if nm == name then ex[#ex + 1] = id end
        end
        if #ex > 0 then ids = ex end
    end
    return ids
end

-- ── 区域截屏（走 sh 脚本：GL 窗口用 root+crop）─────────
function M.shot(x, y, w, h, out)
    M.ensure_display()
    local s = os.getenv("AGENTKIT_SHOT") or "/opt/my-agent/agentkit/bin/shot.sh"
    return os.execute(string.format("%s %d %d %d %d %q", s, x, y, w, h, out))
end

function M.geometry(id)
    M.ensure_display()
    local g = {}
    for k, v in sh(("xdotool getwindowgeometry --shell %d"):format(id)):gmatch("(%a+)=(%-?%d+)") do
        g[k:lower()] = tonumber(v)
    end
    if g.width == nil then return nil end
    return g
end

function M.activate(id)
    M.ensure_display()
    sh(("xdotool windowactivate --sync %d"):format(id))
    sh(("xdotool windowraise %d"):format(id))
end

-- 窗口标题（Chrome 的活动标签页名就在其中）
function M.win_name(id)
    M.ensure_display()
    return (sh(("xdotool getwindowname %d"):format(id)):gsub("\n$", ""))
end

-- ── Window ────────────────────────────────────────────
local Window = {}
Window.__index = Window
M.Window = Window

-- name: 标题子串；opts.class 用 WM_CLASS 精确；opts.pick=索引(默认最后一个=最上层)
function M.window(name, opts)
    M.ensure_display()
    opts = opts or {}
    local ids = M.search(name, opts)
    if #ids == 0 then return nil end
    local id = ids[opts.pick or #ids]
    local g = M.geometry(id) or {}
    return setmetatable({
        id = id, title = name,
        x = g.x or 0, y = g.y or 0, w = g.width or 0, h = g.height or 0,
        lib = lib,
    }, Window)
end

function Window:refresh()
    local g = M.geometry(self.id)
    if g then self.x, self.y, self.w, self.h = g.x, g.y, g.width, g.height end
    return self
end

function Window:activate() M.activate(self.id); return self:refresh() end
function Window:raise() M.activate(self.id) end
function Window:center() lib.ak_center(self.id); return self:refresh() end

function Window:capture(path) return M.shot(self.x, self.y, self.w, self.h, path) end
function Window:capture_region(rx, ry, rw, rh, path)
    return M.shot(self.x + rx, self.y + ry, rw, rh, path)
end

-- 窗口内相对坐标点击
function Window:click(rx, ry) return lib.ak_click(self.x + rx, self.y + ry) end
function Window:move(rx, ry)  return lib.ak_move(self.x + rx, self.y + ry) end

function Window:key(combo) return lib.ak_key(combo) end
function Window:type(s) return lib.ak_type(s) end

-- 在窗口截图内做模板匹配，返回窗口相对中心坐标
function Window:find_image(needle_png, opts)
    opts = opts or {}
    M.ensure_display()
    local tmp = os.getenv("AGENTKIT_TMP") or "/tmp/agentkit"
    os.execute("mkdir -p " .. tmp)
    local hay = string.format("%s/win_%d.png", tmp, self.id % 1000000)
    self:capture(hay)
    local cx, cy, sc = ffi.new("int[1]"), ffi.new("int[1]"), ffi.new("double[1]")
    local r = lib.ak_match(hay, needle_png, opts.thresh or 0.85, cx, cy, sc)
    if r == 1 then return { x = cx[0], y = cy[0], score = sc[0] } end
    return nil
end

function Window:click_image(needle_png, opts)
    local m = self:find_image(needle_png, opts)
    if not m then return false end
    self:click(m.x, m.y)
    return true, m
end

-- 区域截图内容是否发生变化（用于点击后校验）
function Window:changed(before_png, opts)
    opts = opts or {}
    M.ensure_display()
    local tmp = os.getenv("AGENTKIT_TMP") or "/tmp/agentkit"
    os.execute("mkdir -p " .. tmp)
    local after = string.format("%s/win_%d_after.png", tmp, self.id % 1000000)
    if opts.region then
        local r = opts.region
        self:capture_region(r[1], r[2], r[3], r[4], after)
    else
        self:capture(after)
    end
    local d = lib.ak_diff(before_png, after)
    return d, after
end

return M
