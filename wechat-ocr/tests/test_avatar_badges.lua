#!/usr/bin/env luajit
-- WeChat OCR - 第二列头像红点/未读数字检测
-- 1. 检测第二列聊天条目（两行文字区域）
-- 2. 找到每个条目左边的头像
-- 3. 检查头像右上角是否有红点或红底白字数字
-- 4. 输出标注图

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
io.write("=== 第二列头像红点/未读数字检测 ===\n\n"); io.flush()

-- 1. 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)
local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
local win_x = tonumber(geo:match("Position: (%d+)"))
local win_y = tonumber(geo:match(",(%d+)"))
local win_w = tonumber(geo:match("Geometry: (%d+)"))
local win_h = tonumber(geo:match("x(%d+)"))
io.write(string.format("窗口: (%d,%d) %dx%d\n\n", win_x, win_y, win_w, win_h))

-- 2. 截图 + OCR
local screen_shot = "/tmp/wechat_avatar_check.png"
os.execute(string.format("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null",
    win_w, win_h, win_x, win_y, screen_shot))

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

-- 3. 过滤第二列文字
local COL2_MIN = 4
local COL2_MAX = math.floor(win_w * 0.40 + 0.5)
local col2 = {}
for _, b in ipairs(boxes) do
    local rx, ry = b.x, b.y + 35
    if rx >= COL2_MIN and rx <= COL2_MAX and b.h >= 5 and b.w >= 3 then
        table.insert(col2, {rx=rx, ry=ry, w=b.w, h=b.h, text=b.text})
    end
end
table.sort(col2, function(a,b) return a.ry < b.ry end)

-- 4. 找第一个聊天条目的 Y 位置
local row_h = 60
local row_gap = 40
local row_step = row_h + row_gap
local row_w = 545
local row_x = 155

local first_row_y = nil
for _, b in ipairs(col2) do
    if b.ry >= 140 and b.rx >= 50 and b.rx <= 300 and b.h >= 15 then
        first_row_y = b.ry - 5
        break
    end
end

if not first_row_y then io.write("未找到聊天列表\n"); os.exit(0) end

-- 5. 生成聊天条目
local entries = {}
for r = 0, 9 do
    local y = first_row_y + r * row_step
    if y + row_h < win_h - 100 then
        table.insert(entries, {rx=row_x, ry=y, w=row_w, h=row_h, idx=r+1})
    end
end

io.write(string.format("聊天条目: %d 行\n\n", #entries))

-- 6. 检查每个条目的头像红点/数字
-- 头像在文字左侧约 55px，大小约 42x42
local AVATAR_SIZE = 42
local AVATAR_OFFSET = 55  -- 头像右边缘到文字左边缘的距离
local BADGE_SIZE = 16     -- 红点/数字标记的大小

local convert_cmds = {}
local unread_count = 0

-- 检查每行头像右下角是否有红点
-- 红点位置：文字左侧约 5px（头像右侧边缘），行底部向上约 12px
local BADGE_R_OFFSET = 5     -- 红点右边缘到文字左边界的距离
local BADGE_B_OFFSET = 12    -- 红点下边缘到行底部的距离
local BADGE_SIZE_CHECK = 12  -- 检测区域大小

for _, entry in ipairs(entries) do
    local badge_x = entry.rx - BADGE_R_OFFSET - BADGE_SIZE_CHECK
    local badge_y = entry.ry + entry.h - BADGE_B_OFFSET

    local cmd = string.format(
        "convert '%s' +repage -crop %dx%d+%d+%d -format '%%[fx:mean.r],%%[fx:mean.g],%%[fx:mean.b]' info: 2>/dev/null",
        screen_shot, BADGE_SIZE_CHECK, BADGE_SIZE_CHECK, badge_x, badge_y)
    local pipe = io.popen(cmd)
    local info = pipe:read("*a"); pipe:close()
    local r, g, b = info:match("([%d.]+),([%d.]+),([%d.]+)")

    -- R明显高于G表示红色
    if r and tonumber(r) > 0.5 and tonumber(r) > tonumber(g) * 1.8 then
        unread_count = unread_count + 1
        io.write(string.format("  #%d 🔴 (%d,%d) R=%.2f\n", entry.idx, badge_x, badge_y, tonumber(r)))
    end
end

io.write(string.format("\n共 %d 个头像有红点/数字\n", unread_count))

-- 7. 标注图
if #convert_cmds > 0 then
    local home = os.getenv("HOME") or "/home/quqiufeng"
    local annotate = home .. "/wechat_avatar_badges.png"
    local cmd = "convert '" .. screen_shot .. "' " .. table.concat(convert_cmds, " ") ..
                " '" .. annotate .. "' 2>/dev/null"
    os.execute(cmd)
    local fh = io.open(annotate, "r")
    if fh then
        local sz = fh:seek("end"); fh:close()
        io.write(string.format("标注图: %s (%d KB)\n", annotate, sz/1024))
    end
end

io.write("✅\n")
