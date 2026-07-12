#!/usr/bin/env luajit
-- WeChat 第二列红色未读数检测（VLM 语义识别）
-- 方法: 截图 → VLM 识别 → 输出未读数量
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
flush("=== 第二列红色未读数检测（VLM）===\n\n")

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
flush(string.format("窗口: (%d,%d) %dx%d\n\n", wx, wy, ww, wh))

os.execute(string.format("import -window root -crop %dx%d+%d+%d '/tmp/full.png' 2>/dev/null", ww, wh, wx, wy))
os.execute("convert '/tmp/full.png' +repage -crop 445x" .. wh .. "+75+0 +repage '/tmp/col2.png' 2>/dev/null")

-- VLM
flush("[1/2] VLM 识别未读...\n")
local lib = ffi.load("libjoycaption")
local ok = lib.joycaption_init("/data/models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf", "/data/models/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf", 1)
if ok ~= 0 then flush("❌ VLM 加载失败\n"); os.exit(1) end

local prompt = [[Describe each chat item in this WeChat list. For each, tell me the name and if there are any unread message numbers visible.]]
local result = ffi.string(lib.joycaption_analyze("/tmp/col2.png", prompt))
lib.joycaption_free()

flush(string.format("VLM: %s\n\n", result:gsub("\n", " | ")))

-- 解析
flush("[2/2] 结果\n")
local count = 0
for line in result:gmatch("[^\n]+") do
    -- Try "name: number" format
    local name, num = line:match("^(.+):%s*(%d+)$")
    if name and num then
        count = count + 1
        flush(string.format("  %s → %s\n", name, num))
    end
    -- Also look for "unread messages" with number
    local num2, name2 = line:match("(%d+).-unread.-(.+)")
    local num3 = line:match("(%d+).-unread")
    if num3 and not name then
        count = count + 1
        flush(string.format("  %s (from: %s)\n", num3, line:gsub("^%s*", "")))
    end
end
if count == 0 then
    if result:lower():find("none") or result:lower():find("no.*unread") or result:lower():find("no.*badge") then
        flush("  无未读消息\n")
    else
        flush(string.format("  %s\n", result:gsub("\n", "\n  ")))
    end
end
flush("\n✅\n")