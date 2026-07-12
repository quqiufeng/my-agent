#!/usr/bin/env luajit
-- WeChat 第二列红色未读数检测
-- 方法: 红圈检测(确认存在) + VLM整行(读数字)
-- 用法: luajit tests/test_unread_detect.lua

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;/opt/my-agent/wechat-ocr/lua/?.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;/opt/my-agent/wechat-ocr/lib/?.so;;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

-- 截图
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/geo.txt 2>/dev/null")
local f = io.open("/tmp/geo.txt")
local geo = f:read("*a"); f:close()
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
if not wx then io.write("❌ 获取窗口失败\n"); os.exit(1) end

os.execute(string.format("import -window root -crop %dx%d+%d+%d '/tmp/full.png' 2>/dev/null", ww, wh, wx, wy))
os.execute("convert '/tmp/full.png' +repage -crop 445x" .. wh .. "+75+0 +repage '/tmp/col2.png' 2>/dev/null")

-- 找行
io.write("=== 检测未读 ===\n\n"); io.flush()
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
        if h >= 50 and h <= 80 then table.insert(rows, {y=states[i].y}) end
    end
end
local avatars = {}
for _, r in ipairs(rows) do if r.y > 80 then table.insert(avatars, r) end end
io.write(string.format("找到 %d 行\n", #avatars)); io.flush()

-- 检测红圈
io.write("检测红圈...\n"); io.flush()
local badge_rows = {}
for i, a in ipairs(avatars) do
    os.execute(string.format("convert '/tmp/col2.png' +repage -crop 15x15+68+%d +repage '/tmp/_b.png' 2>/dev/null", a.y))
    local rp = io.popen("convert /tmp/_b.png -fx '(r>0.78&&g<0.47&&b<0.47)?1:0' -format '%[fx:mean*100]' info: 2>/dev/null")
    local pct = tonumber(rp:read("*a"):match("[%d.]+")) or 0
    rp:close()
    if pct > 5 then table.insert(badge_rows, a) end
end
io.write(string.format("有红圈: %d 行\n", #badge_rows)); io.flush()

io.write(string.format("\n✅ 共 %d 个未读\n", #badge_rows))

-- 可选：VLM 读数字
if #badge_rows > 0 then
    ffi.cdef[[
        int joycaption_init(const char*, const char*, int);
        const char* joycaption_analyze(const char*, const char*);
        void joycaption_free();
    ]]
    local lib = ffi.load("libjoycaption")
    lib.joycaption_init("/data/models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf", "/data/models/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf", 1)
    io.write("VLM 读数字...\n"); io.flush()

    for _, a in ipairs(badge_rows) do
        os.execute(string.format("convert '/tmp/col2.png' +repage -crop 445x65+0+%d +repage '/tmp/_row.png' 2>/dev/null", a.y))
        local s = ffi.string(lib.joycaption_analyze("/tmp/_row.png", "What number in the red badge? Only answer the digit."))
        local num = s:match("(%d)")
        io.write(string.format("  y=%d → %s\n", a.y, num or "?"))
    end
    lib.joycaption_free()
end

io.write("\n✅\n")