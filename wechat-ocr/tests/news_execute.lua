#!/usr/bin/env luajit
-- news_execute.lua — 检测文件传输助手是否有未读消息
-- 1. 检测第二列红点
-- 2. 找到"文件传输"所在的条目
-- 3. 检查该条目是否有红点（未读）
-- 4. 输出结果（不点击、不读取、不回复）

local ffi = require("ffi")
local cjson = require("cjson")
ffi.cdef[[int usleep(unsigned int);]]

local dir = "/opt/my-agent/wechat-ocr"

-- 检测未读 + 找文件传输助手
local function check()
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    ffi.C.usleep(500000)
    local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
    local win_x = tonumber(geo:match("Position: (%d+)"))
    local win_y = tonumber(geo:match(",(%d+)"))
    local win_w = tonumber(geo:match("Geometry: (%d+)"))
    local win_h = tonumber(geo:match("x(%d+)"))
    if not win_w then return nil, "无法获取窗口" end

    -- 截图
    local shot = "/tmp/wechat_news.png"
    os.execute(string.format("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null", win_w, win_h, win_x, win_y, shot))

    -- OCR
    local lib = ffi.load("libwechat_ocr_core.so")
    ffi.cdef[[
        typedef struct ocr_engine_t ocr_engine_t;
        ocr_engine_t* ocr_create(const char*,const char*,const char*);
        char* ocr_capture_file(ocr_engine_t*, const char*, int, int);
        void ocr_free_string(char*);
        void ocr_destroy(ocr_engine_t*);
    ]]
    local e = lib.ocr_create(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
                              dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
                              dir.."/ppocr_keys_v1.txt")
    local s = lib.ocr_capture_file(e, shot, win_x, win_y)
    lib.ocr_destroy(e)
    if not s or s == ffi.NULL then return nil, "OCR失败" end

    local d = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)
    local boxes = d.boxes or {}

    -- 找到"文件传输"文字位置（相对窗口坐标）
    local ft_x, ft_y = nil, nil
    for _, b in ipairs(boxes) do
        if b.text:find("文件传输") then
            ft_x, ft_y = b.x, b.y + 35  -- 客户区坐标
            break
        end
    end

    if not ft_x then
        return {found=false, reason="未找到文件传输助手条目"}
    end

    -- 检查文件传输助手所在的区域是否有红点
    -- 用 ImageMagick 扫瞄该行左侧区域
    local check_cmd = string.format(
        "convert '%s' +repage -crop %dx%d+%d+%d -fx '(r>g*2.2&&r>b*2.2&&r>0.7&&g<0.5)?1:0' -format '%%[fx:mean*100]' info: 2>/dev/null",
        shot, 40, 40, ft_x - 55, ft_y - 10)
    local pipe = io.popen(check_cmd)
    local red_pct = pipe:read("*a"); pipe:close()
    local has_unread = red_pct and tonumber(red_pct) > 1

    return {
        found = true,
        has_unread = has_unread,
        x = ft_x,
        y = ft_y,
        red_pct = red_pct
    }
end

-- 主流程
local result = check()
if not result then
    io.write("检测失败\n")
    os.exit(1)
end

if result.found then
    if result.has_unread then
        io.write(string.format("文件传输助手有未读消息 (红点 %.1f%%)\n", tonumber(result.red_pct or 0)))
    else
        io.write("文件传输助手无未读消息\n")
    end
else
    io.write(result.reason .. "\n")
end
