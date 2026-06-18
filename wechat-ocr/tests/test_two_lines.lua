#!/usr/bin/env luajit
-- WeChat OCR - 第二列聊天列表条目检测 + 自动操作
-- 1. 点击微信图标
-- 2. 点击第一列第一个小图标，显示聊天列表
-- 3. OCR 全窗口，找第一个聊天条目配对
-- 4. 等距复制 5 行（行高60px，间隔40px）
-- 5. 标注图片到 ~/wechat_two_lines_annotated.png
-- 6. 依次点击/悬停每个条目（服务号只悬停不点击）

local ffi = require("ffi")
local cjson = require("cjson")
ffi.cdef[[void usleep(unsigned int);]]

local lib = ffi.load("libwechat_ocr_core.so")
ffi.cdef[[
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*,const char*,const char*);
    char* ocr_capture_all(ocr_engine_t*);
    char* ocr_capture_file(ocr_engine_t*, const char*, int, int);
    void ocr_free_string(char*);
    void ocr_destroy(ocr_engine_t*);
]]

local dir = "/opt/my-agent/wechat-ocr"
io.write("=== 第二列两行文字区域标注 ===\n\n"); io.flush()

-- 1. 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)
local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
local win_x = tonumber(geo:match("Position: (%d+)"))
local win_y = tonumber(geo:match(",(%d+)"))
local win_w = tonumber(geo:match("Geometry: (%d+)"))
local win_h = tonumber(geo:match("x(%d+)"))

-- 2. 点第一列第一个小图标，确保显示微信聊天列表
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", win_x+40, win_y+110))
ffi.C.usleep(500000)

-- 鼠标移走，避免触发第二列下拉框
os.execute("xdotool mousemove 0 0 2>/dev/null")
ffi.C.usleep(200000)
io.write(string.format("窗口位置: 屏幕 (%d,%d)  %dx%d\n\n", win_x, win_y, win_w, win_h))

-- 截窗口
local screen_shot = "/tmp/wechat_two_lines.png"
os.execute(string.format("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null",
    win_w, win_h, win_x, win_y, screen_shot))

-- OCR
local e = lib.ocr_create(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
                          dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
                          dir.."/ppocr_keys_v1.txt")
local s = lib.ocr_capture_file(e, screen_shot, win_x, win_y)
lib.ocr_destroy(e)
if not s or s == ffi.NULL then io.write("OCR 失败\n"); os.exit(1) end

local d = cjson.decode(ffi.string(s))
lib.ocr_free_string(s)
local boxes = d.boxes or {}
local win = d.win

-- 过滤第二列文字
-- OCR b.x/b.y 相对于 ROI(panel(0,35, w, h-220))
-- 客户区坐标: rx = b.x,  ry = b.y + 35
-- 第二列范围（聊天列表，约为窗口宽度40%）
local COL2_MIN = 4
local COL2_MAX = math.floor(win_w * 0.40 + 0.5)
local col2 = {}
for _, b in ipairs(boxes) do
    local rx, ry = b.x, b.y + 35
    if rx >= COL2_MIN and rx <= COL2_MAX and b.h >= 5 and b.w >= 3 then
        table.insert(col2, {rx=rx, ry=ry, w=b.w, h=b.h, cx=rx+b.w/2, cy=ry+b.h/2, text=b.text})
    end
end
table.sort(col2, function(a,b) return a.ry < b.ry end)

local row_h = 60   -- 文字块高度
local row_gap = 40  -- 文字块间间隔
local row_step = row_h + row_gap  -- 步进
local row_w = 545  -- 固定宽度
local row_x = 155  -- 固定左边界

-- 找第二列第一个聊天条目名称（有预览就配对取Y，没有就用名称本身的Y）
local first_row_y = nil
for _, b in ipairs(col2) do
    if b.ry >= 140 and b.rx >= 50 and b.rx <= 300 and b.h >= 15 then
        first_row_y = b.ry - 5
        break
    end
end

if not first_row_y then
    io.write("未找到聊天列表\n")
    os.exit(0)
end

-- 等距往下复制，间隔20px
local results = {}
local total_rows = 5
for r = 0, total_rows - 1 do
    local y = first_row_y + r * row_step
    if y + row_h < win_h - 100 then  -- 不超过窗口可见范围
        table.insert(results, {rx=row_x, ry=y, w=row_w, h=row_h, idx=r+1})
    end
end

-- ========== 输出结果 ==========
io.write(string.format("第一行: y=%d h=%d x=%d w=%d\n", first_row_y, row_h, row_x, row_w))
io.write(string.format("OCR 找到 %d 个文字框，第二列 %d 个\n\n", #boxes, #col2))
io.write("--- 两行文字区域 ---\n\n")

local convert_cmds = {}
for gi, g in ipairs(results) do
    local min_x, min_y = g.rx, g.ry
    local max_x, max_y = g.rx + g.w, g.ry + g.h

    io.write(string.format(
        "  #%d 行: (%d,%d) %dx%d\n",
        g.idx, min_x, min_y, max_x-min_x, max_y-min_y))

    -- ImageMagick 标注
    table.insert(convert_cmds, string.format(
        '-fill none -stroke red -strokewidth 2 -draw "rectangle %d,%d %d,%d"',
        min_x, min_y, max_x, max_y))
    table.insert(convert_cmds, string.format(
        '-fill red -pointsize 14 -annotate +%d+%d "#%d"',
        min_x+2, min_y-3, g.idx))
end
io.write("\n")

-- 生成标注图
local home = os.getenv("HOME") or "/home/quqiufeng"
local annotate = home .. "/wechat_two_lines_annotated.png"
local cmd = "convert '" .. screen_shot .. "' " .. table.concat(convert_cmds, " ") ..
            " '" .. annotate .. "' 2>/dev/null"
os.execute(cmd)
local fh = io.open(annotate, "r")
if fh then
    local sz = fh:seek("end"); fh:close()
    io.write(string.format("标注图: %s (%d KB)\n", annotate, sz/1024))
end

io.write(string.format("行高=%dpx 间隔=%dpx 共%d行\n", row_h, row_gap, #results))

-- 依次操作五个文字块
io.write("\n--- 依次操作 ---\n")
for gi, g in ipairs(results) do
    local cx = win_x + g.rx + g.w / 2
    local cy = win_y + g.ry + g.h / 2

    -- 检查这一行是否有"服务号"
    local is_service = false
    for _, b in ipairs(col2) do
        if b.ry >= g.ry and b.ry <= g.ry + g.h and
           b.rx >= g.rx and b.rx <= g.rx + g.w then
            if b.text:match("服务号") then
                is_service = true
                break
            end
        end
    end

    if is_service then
        io.write(string.format("  #%d 悬停 (%d,%d) [服务号]\n", g.idx, cx, cy))
        os.execute(string.format("xdotool mousemove %d %d 2>/dev/null", cx, cy))
    else
        io.write(string.format("  #%d 点击 (%d,%d)\n", g.idx, cx, cy))
        os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", cx, cy))
    end
    ffi.C.usleep(800000)
end
io.write("完成\n")
