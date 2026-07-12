package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;./lua/?.lua;./?.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local icon_actions = require("icon_actions")
local ocr = require("wechat_ocr")
local dir = "/opt/my-agent/wechat-ocr"

local ok, err = ocr.init(
    dir.."/models/ch_PP-OCRv4_det_infer.onnx",
    dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
    dir.."/ppocr_keys_v1.txt"
)
if not ok then print("OCR init failed: "..tostring(err)); os.exit(1) end

os.execute("xdotool search --name '微信' windowactivate --sync 2>/dev/null")
ffi.C.usleep(500000)

local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
if not wx then print("no window"); os.exit(1) end

os.execute(string.format("import -window root -crop %dx%d+%d+%d '/tmp/wx_tip_scan.png' 2>/dev/null", ww, wh, wx, wy))

local COL1 = 75
local all_lines = {}
for _, thr in ipairs({5, 10, 20}) do
    local cmd = string.format(
        "convert '/tmp/wx_tip_scan.png' +repage -crop %dx%d+0+0 +repage -colorspace gray -canny 0x1+%d%%%%+%d%%%% " ..
        "-negate -define connected-components:verbose=true -connected-components 4 /dev/null 2>&1 " ..
        "| grep -v 'bgcolor\\|id:\\|0:.*gray'", COL1, wh, thr, thr*2)
    local pipe = io.popen(cmd)
    if pipe then
        for line in pipe:lines() do
            local id, w, h, x, y, area = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
            if w and h then
                table.insert(all_lines, {x=tonumber(x), y=tonumber(y), w=tonumber(w), h=tonumber(h), a=tonumber(area)})
            end
        end
        pipe:close()
    end
end

local tmp = {}
for _, b in ipairs(all_lines) do
    local ratio = b.w / b.h
    if b.h >= 6 and b.w >= 6 and ratio >= 0.3 and ratio <= 3.5 and b.a >= 15 and b.a <= 5000 then
        b.cx = b.x + b.w / 2; b.cy = b.y + b.h / 2
        table.insert(tmp, b)
    end
end
table.sort(tmp, function(a,b) return b.a < a.a end)
local merged = {}
for _, b in ipairs(tmp) do
    local dup = false
    for _, m in ipairs(merged) do
        if (b.cx-m.cx)^2 + (b.cy-m.cy)^2 < 900 then dup = true; break end
    end
    if not dup then table.insert(merged, b) end
end
table.sort(merged, function(a,b) return a.y < b.y end)

print(string.format("Window: %dx%d+%d+%d", ww, wh, wx, wy))
print(string.format("Found %d icons, hovering to read tooltips...\n", #merged))

for i, icon in ipairs(merged) do
    local sx = wx + icon.cx
    local sy = wy + icon.cy
    os.execute(string.format("xdotool mousemove %d %d 2>/dev/null", sx, sy))
    ffi.C.usleep(400000)

    -- OCR 全屏
    local data, _ = ocr.capture_raw()
    if not data or not data.boxes then
        print(string.format("  Icon %d: no OCR data", i))
    else
        local tips = {}
        for _, b in ipairs(data.boxes) do
            local tip_x = b.x + b.w / 2
            local tip_y = b.y + b.h / 2
            -- 图标右侧区域（水平：图标列右侧~210px，垂直：图标附近±30px）
            local icon_abs_x = wx + icon.cx
            local icon_abs_y = wy + icon.cy
            if tip_x > icon_abs_x and tip_x < icon_abs_x + 120
               and math.abs(tip_y - icon_abs_y) < 30 then
                table.insert(tips, b.text)
            end
        end
        if #tips > 0 then
            local text = table.concat(tips, " | ")
            local entry = icon_actions.lookup(tips[1])
            local func = entry and (" → " .. entry.name_cn) or ""
            print(string.format("  Icon %d @(%d,%d): '%s'%s", i, icon.cx, icon.cy, text, func))
        else
            print(string.format("  Icon %d @(%d,%d): (no tooltip detected)", i, icon.cx, icon.cy))
        end
    end
end

ocr.destroy()
os.execute("rm -f /tmp/wx_tip_scan.png")
