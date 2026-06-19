#!/usr/bin/env luajit
-- ============================================================
-- WeChat OCR - 全窗口小图标检测（纯 Lua + ImageMagick）
-- ============================================================
-- 功能: 激活微信 → 截图 → ImageMagick分析 → 标注所有小图标
--
-- 一键测试命令:
--   cd /opt/my-agent/wechat-ocr && \
--   export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib && \
--   export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;" && \
--   export LUA_CPATH="/usr/local/lualib/?.so;;" && \
--   luajit tests/test_icons.lua
--
-- ============================================================
-- 算法说明:
--   1) 多阈值二值化（180→5，步长-5），threshold+negate找暗色区域
--   2) ImageMagick connected-components 提取所有blob
--   3) 基础过滤：6×6px / 宽高比0.35~2.2 / 面积36~4000
--   4) 文字行过滤：±15px Y内、间距<45px的邻居≥4个 → 文字
--   5) 去重标注输出
-- ============================================================

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

io.write("=== 全窗口小图标检测 ===\n\n"); io.flush()

-- 1. 激活微信
io.write("[1/4] 激活微信...\n"); io.flush()
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 2. 获取窗口几何
local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
if not wx then io.write("❌ 获取窗口失败\n"); os.exit(1) end
io.write(string.format("  窗口: (%d,%d) %dx%d\n", wx, wy, ww, wh)); io.flush()

-- 3. 截图
local ts = os.date("%Y%m%d_%H%M%S")
local home = os.getenv("HOME")
local raw = "/tmp/wx_icons_raw.png"
local outfile = home .. "/wechat_icons_" .. ts .. ".png"

os.execute(string.format("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null", ww, wh, wx, wy, raw))

-- 4. 多阈值检测图标
io.write("[2/4] 多阈值检测图标...\n"); io.flush()

local function parse_components(cmd)
    local blobs = {}
    local pipe = io.popen(cmd)
    if not pipe then return blobs end
    for line in pipe:lines() do
        -- 格式: "id: WxH+X+Y centroid_x,centroid_y area mean-color"
        -- 跳过标题行和背景(id=0)
        if line:match("^%s*%d+:") and not line:match("^%s*0:") then
            local id, w, h, x, y, area = line:match(
                "(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
            if w and h and x and y and area then
                table.insert(blobs, {
                    x = tonumber(x), y = tonumber(y),
                    w = tonumber(w), h = tonumber(h),
                    area = tonumber(area)
                })
            end
        end
    end
    pipe:close()
    return blobs
end

local all_blobs = {}
for thr = 180, 5, -5 do
    local pct = thr / 255 * 100
    local cmd = string.format(
        "convert '%s' -colorspace gray -threshold %.1f%%%% -negate " ..
        "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1",
        raw, pct)
    local blobs = parse_components(cmd)
    for _, b in ipairs(blobs) do
        table.insert(all_blobs, b)
    end
end

io.write(string.format("  多阈值原始blob: %d\n", #all_blobs)); io.flush()

-- 基础过滤 + 去重
local filtered = {}
local seen = {}
for _, b in ipairs(all_blobs) do
    local ratio = b.w / b.h
    if b.h >= 5 and b.w >= 5
       and ratio >= 0.3 and ratio <= 2.5
       and b.area >= 25 and b.area <= 4000 then
        local key = math.floor(b.x/8) * 10000 + math.floor(b.y/8)
        if not seen[key] then
            seen[key] = true
            table.insert(filtered, b)
        end
    end
end

table.sort(filtered, function(a,b) return a.y < b.y end)
io.write(string.format("  过滤后: %d\n", #filtered)); io.flush()

-- 文字行过滤
local is_text = {}
for i = 1, #filtered do is_text[i] = false end

for i = 1, #filtered do
    if is_text[i] then goto continue end
    local a = filtered[i]
    local neighbors = {}
    for j = 1, #filtered do
        if i ~= j and not is_text[j] then
            local b = filtered[j]
            local dy = math.abs((a.y + a.h/2) - (b.y + b.h/2))
            local dx = math.abs((a.x + a.w/2) - (b.x + b.w/2))
            if dy <= 15 and dx <= 45 then
                table.insert(neighbors, j)
            end
        end
    end
    if #neighbors >= 4 then
        is_text[i] = true
        for _, j in ipairs(neighbors) do is_text[j] = true end
    end
    ::continue::
end

local icons = {}
for i, b in ipairs(filtered) do
    if not is_text[i] then table.insert(icons, b) end
end

io.write(string.format("  文字行过滤后: %d\n\n", #icons)); io.flush()

-- 5. 标注输出
io.write("[3/4] 标注输出...\n"); io.flush()

local annotate_cmds = {}
table.insert(annotate_cmds, string.format(
    '-fill "rgb(0,255,0)" -pointsize 18 -annotate +10+10 "全窗口 %d 个小图标"', #icons))

for i, b in ipairs(icons) do
    table.insert(annotate_cmds, string.format(
        '-fill none -stroke "rgb(0,255,0)" -strokewidth 1 -draw "rectangle %d,%d %d,%d"',
        b.x, b.y, b.x + b.w, b.y + b.h))
    if b.y >= 12 then
        table.insert(annotate_cmds, string.format(
            '-fill "rgb(0,255,0)" -pointsize 10 -annotate +%d+%d "%d"',
            b.x, b.y - 10, i))
    end
end

local annotate = table.concat(annotate_cmds, " ")
local draw_cmd = string.format("convert '%s' %s '%s' 2>/dev/null", raw, annotate, outfile)
os.execute(draw_cmd)

local fh = io.open(outfile, "r")
if fh then
    local sz = fh:seek("end"); fh:close()
    io.write(string.format("  标记图: %s (%d KB)\n", outfile, sz/1024))
end

-- 6. 隐藏微信
io.write("[4/4] 隐藏微信...\n"); io.flush()
os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
io.write("  微信已隐藏\n")
