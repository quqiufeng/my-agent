package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;./lua/?.lua;./?.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local ocr = require("wechat_ocr")
local dir = "/opt/my-agent/wechat-ocr"
local ok, err = ocr.init(dir.."/models/ch_PP-OCRv4_det_infer.onnx", dir.."/models/ch_PP-OCRv4_rec_infer.onnx", dir.."/ppocr_keys_v1.txt")
if not ok then print("OCR fail: "..tostring(err)); return end

local robot = require("wechat_robot")
robot.init()

local icons, err = robot.scan_icons()
if not icons then print("scan fail: "..tostring(err)); return end
print("Icons detected by VLM:\n")

-- 点窗口左上角获取内部焦点
local win = robot.get_window_rect()
if win then
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", win.x + 5, win.y + 5))
    ffi.C.usleep(800000)
end

-- baseline: 无 hover 时所有文字
local function collect(data)
    local t = {}
    if data and data.boxes then
        for _, b in ipairs(data.boxes) do t[b.y..":"..b.x] = b.text end
    end
    return t
end
local baseline = collect(ocr.capture_raw())

for i, icon in ipairs(icons) do
    if not icon.pos then
        print(string.format("  %d. %s: no position", i, icon.name))
        goto continue
    end

    -- hover 到 VLM 给出的精确位置
    os.execute(string.format("xdotool mousemove %d %d 2>/dev/null", icon.pos.x, icon.pos.y))
    ffi.C.usleep(800000)

    -- OCR 找新出现的短中文文字
    local data, _ = ocr.capture_raw()
    local tip = "?"
    if data and data.boxes then
        for _, b in ipairs(data.boxes) do
            local dy = b.y + b.h/2 - icon.pos.y
            local len = #(b.text or "")
            if math.abs(dy) < 35 and len >= 3 and len <= 12 and b.text:match("[\200-\237]") then
                local key = b.y .. ":" .. b.x
                if not baseline[key] then
                    tip = b.text
                    break
                end
            end
        end
    end

    print(string.format("  %d. %-12s → '%s' @(%d,%d)", i, icon.name, tip, icon.pos.x, icon.pos.y))

    ::continue::
end

robot.vlm_free()
ocr.destroy()
