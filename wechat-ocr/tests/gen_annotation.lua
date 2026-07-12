#!/usr/bin/env luajit
-- 生成带标记的 WeChat 窗口截图

package.path = "/opt/my-agent/wechat-ocr/lua/?.lua;" .. (package.path or "")

local cjson = require("cjson")
local home = os.getenv("HOME")

local f = io.open(home .. "/.wechat_icons.json")
if not f then print("❌ ~/.wechat_icons.json 不存在"); os.exit(1) end
local config = cjson.decode(f:read("*a"))
f:close()

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
os.execute("sleep 0.5")
os.execute("xdotool getactivewindow getwindowgeometry > /tmp/wx_geo.txt 2>/dev/null")
f = io.open("/tmp/wx_geo.txt")
local geo = f:read("*a"); f:close()
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
if not wx then print("❌ 获取窗口失败"); os.exit(1) end

local output = "/tmp/wx_anno_full.png"
os.execute(string.format("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null", ww, wh, wx, wy, output))

-- 用 convert 分批绘制，不删除中间文件便于调试
local tmp = "/tmp/wx_anno_stage.png"

-- 1. 侧边栏矩形
os.execute(string.format("cp '%s' '%s'", output, tmp))
for _, icon in ipairs(config.sidebar) do
    local x1 = icon.rel_x - math.floor(icon.w / 2) - 2
    local y1 = icon.rel_y - math.floor(icon.h / 2) - 2
    local x2 = x1 + icon.w + 4
    local y2 = y1 + icon.h + 4
    -- 半透明填充
    os.execute(string.format("convert '%s' -fill 'rgba(0,255,0,0.2)' -draw 'rectangle %d,%d %d,%d' '%s' 2>/dev/null",
        tmp, x1, y1, x2, y2, tmp))
    -- 绿色边框
    os.execute(string.format("convert '%s' -fill none -stroke lime -strokewidth 2 -draw 'rectangle %d,%d %d,%d' '%s' 2>/dev/null",
        tmp, x1, y1, x2, y2, tmp))
    -- 标签（在矩形上方偏左）
    local label = icon.name_cn .. "(" .. icon.name .. ")"
    os.execute(string.format(
        "convert '%s' -fill white -stroke black -strokewidth 1 -font /usr/share/fonts/truetype/wqy/wqy-microhei.ttc -pointsize 12 " ..
        "-annotate +%d+%d '%s' '%s' 2>/dev/null",
        tmp, x1, math.max(y1 - 6, 12), label, tmp))
end

-- 2. 工具栏矩形
for _, icon in ipairs(config.toolbar) do
    local x1 = icon.rel_x - math.floor(icon.w / 2) - 2
    local y1 = icon.rel_y - math.floor(icon.h / 2) - 2
    local x2 = x1 + icon.w + 4
    local y2 = y1 + icon.h + 4
    os.execute(string.format("convert '%s' -fill 'rgba(30,144,255,0.2)' -draw 'rectangle %d,%d %d,%d' '%s' 2>/dev/null",
        tmp, x1, y1, x2, y2, tmp))
    os.execute(string.format("convert '%s' -fill none -stroke dodgerblue -strokewidth 2 -draw 'rectangle %d,%d %d,%d' '%s' 2>/dev/null",
        tmp, x1, y1, x2, y2, tmp))
    local label = icon.name_cn .. "(" .. icon.name .. ")"
    os.execute(string.format(
        "convert '%s' -fill white -stroke black -strokewidth 1 -font /usr/share/fonts/truetype/wqy/wqy-microhei.ttc -pointsize 12 " ..
        "-annotate +%d+%d '%s' '%s' 2>/dev/null",
        tmp, x1, math.max(y1 - 6, 12), label, tmp))
end

-- 3. 图例
os.execute(string.format("convert '%s' -fill 'rgba(0,0,0,0.5)' -draw 'rectangle 5,5 230,55' -fill lime -draw 'rectangle 12,14 26,26' '%s' 2>/dev/null", tmp, tmp))
os.execute(string.format("convert '%s' -fill white -stroke none -font /usr/share/fonts/truetype/wqy/wqy-microhei.ttc -pointsize 14 -annotate +32+28 '左侧第一列 (Sidebar)' '%s' 2>/dev/null", tmp, tmp))
os.execute(string.format("convert '%s' -fill dodgerblue -draw 'rectangle 12,36 26,48' -fill white -font /usr/share/fonts/truetype/wqy/wqy-microhei.ttc -pointsize 14 -annotate +32+50 '右侧第三列 (Toolbar)' '%s' 2>/dev/null", tmp, tmp))

-- 复制到 home
local final = home .. "/wechat_icons_annotated.png"
os.execute(string.format("cp '%s' '%s'", tmp, final))

print(string.format("✅ %s", final))
print(string.format("   侧边栏: %d 个, 工具栏: %d 个", #config.sidebar, #config.toolbar))
