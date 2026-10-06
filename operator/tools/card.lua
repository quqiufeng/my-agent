-- operator/tools/card.lua — 用 /opt/WordCard 的 libtxt2png.so 渲染漂亮卡片（HarfBuzz+Cairo，纯 C ABI）
-- 用法: luajit card.lua <out.png> <大字> <小字> [宽] [高] [背景hex] [大字色hex] [小字色hex]
local ffi = require("ffi")
ffi.cdef[[
typedef void* txt2png_canvas_t;
txt2png_canvas_t txt2png_canvas_create(int width, int height, uint32_t bg_color);
void            txt2png_canvas_destroy(txt2png_canvas_t canvas);
int             txt2png_canvas_draw_text(txt2png_canvas_t canvas, const char* font_path, double font_size, const char* text, int x, int baseline_y, uint32_t color);
int             txt2png_canvas_measure(txt2png_canvas_t canvas, const char* font_path, double font_size, const char* text);
int             txt2png_canvas_save(txt2png_canvas_t canvas, const char* output_path);
int             txt2png_canvas_ascent(txt2png_canvas_t canvas, const char* font_path, double font_size);
]]

local function hx(s, def)
    if not s or s == "" then return def end
    return tonumber(s:gsub("^0x", ""), 16) or def
end

local out     = arg[1] or "/tmp/myagent_card.png"
local big     = arg[2] or ""
local sub     = arg[3] or ""
local W       = tonumber(arg[4]) or 1000
local H       = tonumber(arg[5]) or 600
local bg      = hx(arg[6], 0x0b1f12)
local bigcol  = hx(arg[7], 0xf4f4f4)
local subcol  = hx(arg[8], 0x9fe0b0)

local FONT_EN = "/opt/WordCard/JetBrainsMono-Bold.ttf"
local FONT_ZH = "/opt/WordCard/LXGWWenKai-Regular.ttf"

local lib = ffi.load("/opt/WordCard/src/libtxt2png.so")
local c = lib.txt2png_canvas_create(W, H, bg)

-- 大字自适应字号
local bsize = 170
local blen = #big
if blen > 10 then bsize = 120 end
if blen > 14 then bsize = 92 end
if blen > 20 then bsize = 70 end

local function centered(font, size, text, baseline, color)
    local w = lib.txt2png_canvas_measure(c, font, size, text)
    local x = math.floor((W - w) / 2)
    if x < 10 then x = 10 end
    lib.txt2png_canvas_draw_text(c, font, size, text, x, math.floor(baseline), color)
end

centered(FONT_EN, bsize, big, H * 0.46, bigcol)
if sub ~= "" then
    local ssize = 56
    if #sub > 20 then ssize = 44 end
    if #sub > 30 then ssize = 34 end
    centered(FONT_ZH, ssize, sub, H * 0.80, subcol)
end

local rc = lib.txt2png_canvas_save(c, out)
lib.txt2png_canvas_destroy(c)
os.exit(rc == 0 and 0 or 1)
