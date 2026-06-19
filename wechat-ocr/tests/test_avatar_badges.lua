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
-- 用连通分量分析找头像区域的红色小点（红点和数字）
-- 先生成整个窗口的红色掩码，再用连通分量找小区域
local red_mask = "/tmp/_red_mask.png"
os.execute(string.format(
    "convert '%s' +repage -fx '(r>g*2.2&&r>b*2.2&&r>0.7&&g<0.5)?1:0' '%s' 2>/dev/null",
    screen_shot, red_mask))

-- 连通分量分析
local pipe_cc = io.popen(string.format(
    "convert '%s' -define connected-components:verbose=true -connected-components 4 '%s' 2>/dev/null | grep -v 'bgcolor\\|id:\\|0:'",
    red_mask, "/dev/null"))
local cc_output = pipe_cc:read("*a"); pipe_cc:close()

-- 解析每个连通分量，找到位于聊天条目区域的红色小点
local red_dots = {}
for line in cc_output:gmatch("[^\n]+") do
    local id, w, h, x, y, pixels = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
    if w and h and x and y and pixels then
        local nw, nh, nx, ny, np = tonumber(w), tonumber(h), tonumber(x), tonumber(y), tonumber(pixels)
        -- 小红点：5~20px，左侧（x<200），有效像素数 >= 20
        if nw >= 5 and nh >= 5 and nw <= 20 and nh <= 20 and nx < 200 and np >= 20 then
            table.insert(red_dots, {x = nx, y = ny, w = nw, h = nh, px = np})
        end
    end
end

-- 匹配红点到聊天条目
for _, dot in ipairs(red_dots) do
    local dot_cy = dot.y + dot.h / 2
    for _, entry in ipairs(entries) do
        -- 红点必须在条目垂直范围内（允许上方 30px 偏差）
        if dot_cy >= entry.ry - 30 and dot_cy <= entry.ry + entry.h + 10 then
            -- 红点离文字左侧的距离（服务号/公众号可能偏左）
            local dist_to_text = entry.rx - dot.x
            if dist_to_text >= 5 and dist_to_text <= 50 then
                if not entry.found then
                    entry.found = true
                    entry.dot_x = dot.x
                    entry.dot_y = dot.y
                end
                break
            end
        end
    end
end

-- 检查 OCR 文本中的 "*条" 模式（群消息计数）
for _, entry in ipairs(entries) do
    if not entry.found then
        for _, b in ipairs(col2) do
            if b.ry >= entry.ry - 10 and b.ry <= entry.ry + entry.h and
               b.rx >= entry.rx - 60 and b.rx <= entry.rx + entry.w and
               (b.text:match("%d+条") or b.text:match("%d+条")) then
                entry.found = true
                entry.dot_x = b.rx + b.w / 2
                entry.dot_y = b.ry + b.h / 2
                entry.from_text = true
                break
            end
        end
    end
end

-- 未匹配的红点不计数（日志输出）
for _, dot in ipairs(red_dots) do
    local matched = false
    for _, entry in ipairs(entries) do if entry.found and entry.dot_x == dot.x then matched = true; break end end
    if not matched then
        io.write(string.format("  忽略: 未匹配红点 (%d,%d) %dx%d\n", dot.x, dot.y, dot.w, dot.h))
    end
end

-- 处理匹配到条目的红点（仅这些计入未读）
for _, entry in ipairs(entries) do
    if entry.found then
        unread_count = unread_count + 1
        local tag = entry.from_text and "📝" or "🔴"
        io.write(string.format("  #%d %s (%d,%d)\n", entry.idx, tag, entry.dot_x, entry.dot_y))
        -- 标注整个文字块（红框 + 编号）
        table.insert(convert_cmds, string.format(
            '-fill none -stroke red -strokewidth 2 -draw "rectangle %d,%d %d,%d"',
            entry.rx, entry.ry, entry.rx + entry.w, entry.ry + entry.h))
        table.insert(convert_cmds, string.format(
            '-fill red -pointsize 14 -annotate +%d+%d "#%d 🔴"',
            entry.rx + 2, entry.ry - 4, entry.idx))
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
