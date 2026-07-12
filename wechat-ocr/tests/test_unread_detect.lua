#!/usr/bin/env luajit
-- WeChat 第二列红色未读数检测
-- 方法: 截图 → 投影找行 → VLM 逐行确认数字
-- 用法: luajit tests/test_unread_detect.lua

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
flush("=== 第二列红色未读数检测 ===\n\n")

-- 截图
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/wx_geo.txt 2>/dev/null")
local f = io.open("/tmp/wx_geo.txt")
local geo = f:read("*a"); f:close()
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
if not wx then flush("❌ 获取窗口失败\n"); os.exit(1) end

os.execute(string.format("import -window root -crop %dx%d+%d+%d '/tmp/full.png' 2>/dev/null", ww, wh, wx, wy))
os.execute("convert '/tmp/full.png' +repage -crop 445x" .. wh .. "+75+0 +repage '/tmp/col2.png' 2>/dev/null")

-- 垂直投影找行
flush("[1/3] 垂直投影找行...\n")
local pipe = io.popen("convert '/tmp/col2.png' -crop 60x+15+0 +repage -colorspace gray -scale 1x" .. wh .. "! txt:- 2>/dev/null | grep -oP 'gray\\(\\K[0-9.]+'")
local states, prev_v, y = {}, 255, 0
for line in pipe:lines() do
    local v = tonumber(line)
    if v then
        if v < 200 and prev_v >= 210 then table.insert(states, {type="start", y=y})
        elseif v >= 210 and prev_v < 200 then table.insert(states, {type="end", y=y}) end
        prev_v = v; y = y + 1
    end
end
pipe:close()

local rows = {}
for i = 1, #states do
    if states[i].type == "start" and i < #states then
        local h = states[i+1].y - states[i].y
        if h >= 50 and h <= 80 then table.insert(rows, {y=states[i].y, h=h}) end
    end
end
local avatars = {}
for _, r in ipairs(rows) do if r.y > 80 then table.insert(avatars, r) end end
flush(string.format("  找到 %d 行\n", #avatars))

-- VLM 逐行
flush("[2/3] VLM 逐行识别...\n")
local lib = ffi.load("libjoycaption")
local ok = lib.joycaption_init("/data/models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf", "/data/models/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf", 1)
if ok ~= 0 then flush("❌ VLM 加载失败\n"); os.exit(1) end

local results = {}
for i, a in ipairs(avatars) do
    -- 提取单行
    os.execute(string.format("convert '/tmp/col2.png' +repage -crop 445x%d+0+%d +repage '/tmp/_row.png' 2>/dev/null", a.h, a.y))
    local prompt = "What number is in the red badge on the avatar's top-right corner? Answer only the number, or 'none' if no badge."

    -- 获取每行原始图片的 VLM 分析
    local s = ffi.string(lib.joycaption_analyze("/tmp/_row.png", prompt))
    local num = s:match("(%d+)")
    if num and tonumber(num) > 0 and tonumber(num) <= 9 then
        table.insert(results, {idx=i, num=num})
        flush(string.format("  #%d: %s\n", i, num))
    else
        flush(string.format("  #%d: -\n", i))
    end
end
lib.joycaption_free()

-- 统计
flush("\n[3/3] 结果\n")
if #results == 0 then
    flush("  无未读消息\n")
else
    flush(string.format("  %d 个未读:\n", #results))
    for _, r in ipairs(results) do flush(string.format("    #%d → %s\n", r.idx, r.num)) end
end
flush("✅\n")