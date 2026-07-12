#!/usr/bin/env luajit
-- 第二列聊天列表标注：VLM 识别 + CC 定位头像 → 标注图
-- 用法: luajit tests/test_col2_annotate.lua

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;/opt/my-agent/wechat-ocr/lua/?.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;/opt/my-agent/wechat-ocr/lib/?.so;;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[
    void usleep(unsigned int);
    int  joycaption_init(const char*, const char*, int);
    const char* joycaption_analyze(const char*, const char*);
    void joycaption_free();
]]

local function flush(s) io.write(s); io.flush() end

-- OCR 初始化（全局复用）
ffi.cdef[[
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*,const char*,const char*);
    char*         ocr_capture(ocr_engine_t*);
    void          ocr_free_string(char*);
    void          ocr_destroy(ocr_engine_t*);
]]
local ocr_lib = ffi.load("libwechat_ocr_core.so")
local ocr_e = ocr_lib.ocr_create(
    "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_det_infer.onnx",
    "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_rec_infer.onnx",
    "/opt/my-agent/wechat-ocr/ppocr_keys_v1.txt")
if not ocr_e or ocr_e == ffi.NULL then flush("❌ OCR 加载失败\n"); os.exit(1) end

flush("=== 第二列聊天列表标注 ===\n\n")

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 获取窗口
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/wx_geo.txt 2>/dev/null")
local f = io.open("/tmp/wx_geo.txt")
local geo = f:read("*a"); f:close()
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
if not wx then flush("❌ 获取窗口失败\n"); os.exit(1) end
flush(string.format("窗口: (%d,%d) %dx%d\n\n", wx, wy, ww, wh))

-- 截全窗
os.execute(string.format("import -window root -crop %dx%d+%d+%d '/tmp/full.png' 2>/dev/null", ww, wh, wx, wy))

-- 裁第二列 (x=75 开始，约 445px 宽)
os.execute("convert '/tmp/full.png' +repage -crop 445x" .. wh .. "+75+0 +repage '/tmp/col2.png' 2>/dev/null")

-- VLM 识别
flush("[1/3] VLM 识别聊天列表...\n")
local lib = ffi.load("libjoycaption")
local ok = lib.joycaption_init("/data/models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf", "/data/models/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf", 1)
if ok ~= 0 then flush("  VLM 加载失败\n"); os.exit(1) end

local prompt = [[List each chat item from top to bottom. Number them. Output only: "1. name"]]
local result = ffi.string(lib.joycaption_analyze("/tmp/col2.png", prompt))
lib.joycaption_free()
flush("  VLM: " .. result:gsub("\n", " | ") .. "\n\n")

-- 解析名字
local names = {}
for line in result:gmatch("[^\n]+") do
    local name = line:match("^%d+%.%s*(.+)$")
    if name then table.insert(names, name) end
end
flush(string.format("  %d 个条目\n\n", #names))

-- 垂直投影法找所有行：取头像列 (x=15~75) 的灰度变化
flush("[2/3] 垂直投影找行...\n")
local proj_cmd = string.format(
    "convert '/tmp/col2.png' -crop 60x+15+0 +repage -colorspace gray " ..
    "-scale 1x%d! txt:- 2>/dev/null | grep -oP 'gray\\(\\K[0-9.]+'",
    wh)
local pipe = io.popen(proj_cmd)
local rows = {}
local states = {}
if pipe then
    local prev_v = 255
    local y = 0
    for line in pipe:lines() do
        local v = tonumber(line)
        if v then
            if v < 200 and prev_v >= 210 then
                table.insert(states, {type="start", y=y, v=v})
            elseif v >= 210 and prev_v < 200 then
                table.insert(states, {type="end", y=y, v=v})
            end
            prev_v = v
            y = y + 1
        end
    end
    pipe:close()
end

-- 配對 start/end 成行
for i = 1, #states do
    if states[i].type == "start" and i < #states then
        local end_y = states[i+1].y
        local h = end_y - states[i].y
        if h >= 50 and h <= 80 then
            table.insert(rows, {start=states[i].y, h=h})
        end
    end
end

flush(string.format("  投影法找到 %d 个行\n", #rows))

-- 过滤：跳过搜索栏区域 y<80
local avatars = {}
for _, r in ipairs(rows) do
    if r.start > 80 then
        table.insert(avatars, {x=15, y=r.start, w=60, h=r.h})
    end
end
flush(string.format("  过滤后 %d 个头像行\n", #avatars))
for i, a in ipairs(avatars) do
    flush(string.format("    %d. y=%d h=%d\n", i, a.y, a.h))
end

for i, a in ipairs(avatars) do
    flush(string.format("  %d. (%d,%d) %dx%d\n", i, a.x, a.y, a.w, a.h))
end
flush("\n")

-- 红色底数字检测
flush("[3/4] 检测红色未读数...\n")
local function check_red_badge(img, ax, ay, ah)
    -- 头像右上角（badge 位置）
    local bw, bh = 24, 24
    local bx = ax + 60 - bw + 2  -- 头像右边缘往左一点
    local by = ay - 3             -- 头像上边缘往上一点
    local crop = string.format("convert '%s' +repage -crop %dx%d+%d+%d '/tmp/badge_chk.png' 2>/dev/null", img, bw, bh, bx, by)
    os.execute(crop)

    -- 红色像素检测 (R>220, G<80, B<80) — 用逐步法避免管道 bug
    os.execute([[convert '/tmp/badge_chk.png' -channel R -separate -threshold 86%% '/tmp/_r.png' 2>/dev/null]])
    os.execute([[convert '/tmp/badge_chk.png' -channel G -separate -threshold 31%% '/tmp/_g.png' 2>/dev/null]])
    os.execute([[convert '/tmp/badge_chk.png' -channel B -separate -threshold 31%% '/tmp/_b.png' 2>/dev/null]])
    os.execute([[convert '/tmp/_g.png' +negate '/tmp/_gn.png' 2>/dev/null]])
    os.execute([[convert '/tmp/_b.png' +negate '/tmp/_bn.png' 2>/dev/null]])
    os.execute([[convert '/tmp/_r.png' '/tmp/_gn.png' '/tmp/_bn.png' -compose multiply -composite -format '%[fx:mean*100]' info: > /tmp/_redpct.txt 2>/dev/null]])
    local rf = io.open("/tmp/_redpct.txt")
    local pct = rf and tonumber(rf:read("*a"):match("[%d.]+")) or 0
    if rf then rf:close() end

    if pct < 2.0 then return nil end  -- 红色不足

    -- 有红色 → OCR 读数字
    local num = ""
    local cjson = require("cjson")
    local s = ocr_lib.ocr_capture(ocr_e)
    if s and s ~= ffi.NULL then
        local text = cjson.decode(ffi.string(s)).text or ""
        num = text:match("^(%d+)") or ""
        ocr_lib.ocr_free_string(s)
    end
    if num == "" then return nil end  -- 只返回带数字的
    return num
end

local badge_items = {}
local n = math.min(#names, #avatars)
for i = 1, n do
    local a = avatars[i]
    local num = check_red_badge("/tmp/col2.png", a.x, a.y, a.h)
    if num then
        table.insert(badge_items, {idx=i, name=names[i], y=a.y, h=a.h, num=num})
        flush(string.format("  #%d %s → 未读:%s\n", i, names[i], num))
    else
        flush(string.format("  #%d %s → 无未读\n", i, names[i]))
    end
end

-- 标注
flush("\n[4/4] 生成标注图...\n")
local anno_cmds = {}
for i = 1, n do
    local a = avatars[i]
    local label = string.format("%d.%s", i, names[i])
    local lx = a.x + a.w + 5
    local ly = a.y + a.h / 2 + 4
    table.insert(anno_cmds, string.format(
        "-fill 'rgba(255,80,80,192)' -draw 'rectangle %d,%d %d,%d' " ..
        "-fill white -font Courier-Bold -pointsize 16 -annotate +%d+%d '%s'",
        lx - 2, a.y - 2, lx + 280, a.y + a.h + 2,
        lx, ly, label))
end

local cmd = "convert '/tmp/col2.png' "
for _, c in ipairs(anno_cmds) do cmd = cmd .. c .. " " end
cmd = cmd .. "'" .. os.getenv("HOME") .. "/col2_annotated.png' 2>/dev/null"
os.execute(cmd)

local home = os.getenv("HOME")
os.execute(string.format("cp '/tmp/col2.png' '%s/col2_raw.png' 2>/dev/null", home))
flush(string.format("  ✅ %s/col2_annotated.png\n", home))
flush(string.format("  ✅ %s/col2_raw.png\n", home))
if #badge_items > 0 then
    flush(string.format("  \n有未读红的聊天:\n"))
    for _, b in ipairs(badge_items) do
        flush(string.format("    #%d %s → %s\n", b.idx, b.name, b.num))
    end
end
