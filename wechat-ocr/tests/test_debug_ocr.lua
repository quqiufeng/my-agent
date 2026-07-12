-- debug: hover first icon → dump all OCR text
package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;./lua/?.lua;./?.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

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
print(string.format("Window: %dx%d+%d+%d", ww, wh, wx, wy))

-- 鼠标移到第一列大概的图标位置
local icon_x = wx + 40
local icon_y = wy + 150

print(string.format("Hovering at (%d, %d)...", icon_x, icon_y))
os.execute(string.format("xdotool mousemove %d %d 2>/dev/null", icon_x, icon_y))
ffi.C.usleep(800000)

-- OCR 全屏
local data, _ = ocr.capture_raw()
if not data then
    print("No OCR data")
    os.exit(1)
end

print(string.format("OCR window: x=%d y=%d w=%d h=%d", data.win.x or 0, data.win.y or 0, data.win.w or 0, data.win.h or 0))
print(string.format("Found %d text boxes:", #(data.boxes or {})))

table.sort(data.boxes or {}, function(a,b) return a.y < b.y end)

for i, b in ipairs(data.boxes or {}) do
    local cx = b.x + b.w/2
    local cy = b.y + b.h/2
    print(string.format("  [%d] '%s' @(%d,%d) size=%dx%d", i, b.text, cx, cy, b.w, b.h))
end

ocr.destroy()
