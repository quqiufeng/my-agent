#!/usr/bin/env luajit
-- news_execute.lua — 检测未读消息 → 识别文件传输助手 → 读取 → 回复
-- 1. 检测第二列红点
-- 2. 找到"文件传输助手"条目如果有未读
-- 3. 点进去读取最新消息
-- 4. 回复"收到！马上处理" + 引用原文

local ffi = require("ffi")
local cjson = require("cjson")
ffi.cdef[[int usleep(unsigned int);]]

local dir = "/opt/my-agent/wechat-ocr"

-- ============ 检测模块 ============

local function detect_unread()
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    ffi.C.usleep(500000)
    local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
    local win_x = tonumber(geo:match("Position: (%d+)"))
    local win_y = tonumber(geo:match(",(%d+)"))
    local win_w = tonumber(geo:match("Geometry: (%d+)"))
    local win_h = tonumber(geo:match("x(%d+)"))
    if not win_w then return nil, "无法获取窗口" end

    local shot = "/tmp/wechat_news.png"
    os.execute(string.format("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null", win_w, win_h, win_x, win_y, shot))

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
    local win = d.win

    -- 过滤第二列
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

    -- 找第一个条目位置
    local row_h, row_gap, row_w, row_x = 60, 40, 545, 155
    local row_step = row_h + row_gap
    local first_row_y = nil
    for _, b in ipairs(col2) do
        if b.ry >= 140 and b.rx >= 50 and b.rx <= 300 and b.h >= 15 then
            first_row_y = b.ry - 5
            break
        end
    end
    if not first_row_y then return nil, "未找到聊天列表" end

    -- 生成条目
    local entries = {}
    for r = 0, 9 do
        local y = first_row_y + r * row_step
        if y + row_h < win_h - 100 then
            table.insert(entries, {rx=row_x, ry=y, w=row_w, h=row_h, idx=r+1})
        end
    end

    -- 红色掩码 + 连通分量
    os.execute(string.format("convert '%s' +repage -fx '(r>g*2.2&&r>b*2.2&&r>0.7&&g<0.5)?1:0' '/tmp/_news_red.png' 2>/dev/null", shot))
    local pipe = io.popen("convert '/tmp/_news_red.png' -define connected-components:verbose=true -connected-components 4 /dev/null 2>/dev/null | grep -v 'bgcolor\\|id:\\|0:'")
    local cc = pipe:read("*a"); pipe:close()

    local red_dots = {}
    for line in cc:gmatch("[^\n]+") do
        local id, w, h, x, y, px = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
        if w and h and x and y and px then
            local nw, nh, nx, ny, np = tonumber(w), tonumber(h), tonumber(x), tonumber(y), tonumber(px)
            if nw >= 5 and nh >= 5 and nw <= 20 and nh <= 20 and nx < 200 and np >= 20 then
                table.insert(red_dots, {x = nx, y = ny, w = nw, h = nh, px = np})
            end
        end
    end

    -- 匹配红点到条目
    for _, dot in ipairs(red_dots) do
        local cy = dot.y + dot.h / 2
        for _, entry in ipairs(entries) do
            if cy >= entry.ry - 30 and cy <= entry.ry + entry.h + 10 then
                local dist = entry.rx - dot.x
                if dist >= 5 and dist <= 50 then
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

    -- *条 文本匹配
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

    return entries, {win_x=win_x, win_y=win_y, win_w=win_w, win_h=win_h}, col2
end

-- ============ 文件传输助手处理 ============

-- 找到文件传输助手条目（有未读的）
local function find_file_transfer(entries, col2)
    for _, entry in ipairs(entries) do
        if entry.found then
            -- 检查该条目区域内的文本是否包含"文件传输助手"
            for _, b in ipairs(col2) do
                if b.ry >= entry.ry - 10 and b.ry <= entry.ry + entry.h and
                   b.text:find("文件传输助手") then
                    return entry
                end
            end
        end
    end
    return nil
end

-- 点击文件传输助手并读取最新消息
local function read_latest_message(entry, win)
    local cx = win.win_x + entry.rx + entry.w / 2
    local cy = win.win_y + entry.ry + entry.h / 2
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", cx, cy))
    ffi.C.usleep(2000000)

    -- 滚动到最新消息（按 End 键或向下滚动）
    os.execute("xdotool key End 2>/dev/null")
    ffi.C.usleep(1000000)

    -- 截图消息区域（第三列）
    local third_col_x = win.win_x + math.floor(win.win_w * 0.40)
    local msg_y = win.win_y + 100
    local msg_h = win.win_h - 250
    os.execute(string.format("import -window root -crop %dx%d+%d+%d '/tmp/_ft_msg.png' 2>/dev/null",
        win.win_w - math.floor(win.win_w * 0.40), msg_h, third_col_x, msg_y))

    -- OCR 读消息
    local lib = ffi.load("libwechat_ocr_core.so")
    local e = lib.ocr_create(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
                              dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
                              dir.."/ppocr_keys_v1.txt")
    local s = lib.ocr_capture_file(e, "/tmp/_ft_msg.png", third_col_x, msg_y)
    local message = ""
    if s and s ~= ffi.NULL then
        local d = cjson.decode(ffi.string(s))
        lib.ocr_free_string(s)
        local lines = {}
        for _, b in ipairs(d.boxes or {}) do
            if #b.text > 2 then table.insert(lines, b.text) end
        end
        message = table.concat(lines, "\n")
    end
    lib.ocr_destroy(e)
    return message
end

-- 回复文件传输助手（引用原文）
local function reply_with_quote(original_msg)
    -- 聚焦输入框（在消息区域底部）
    local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
    local wx = tonumber(geo:match("Position: (%d+)"))
    local wy = tonumber(geo:match(",(%d+)"))
    local ww = tonumber(geo:match("Geometry: (%d+)"))
    local wh = tonumber(geo:match("x(%d+)"))

    -- 点输入框（第三列底部）
    local input_x = wx + math.floor(ww * 0.70)
    local input_y = wy + wh - 80
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", input_x, input_y))
    ffi.C.usleep(500000)

    -- 构造回复内容
    local reply = "收到！马上处理\n\n—— 原文：\n" .. original_msg

    -- 写入剪贴板
    local f = io.open("/tmp/_ft_reply.txt", "w")
    if f then f:write(reply); f:close() end
    os.execute("xclip -selection clipboard < /tmp/_ft_reply.txt 2>/dev/null")
    ffi.C.usleep(200000)

    -- 粘贴 + 发送
    os.execute("xdotool key ctrl+v 2>/dev/null")
    ffi.C.usleep(300000)
    os.execute("xdotool key Return 2>/dev/null")

    return reply
end

-- ============ 主流程 ============

io.write("=== 文件传输助手消息检测 ===\n"); io.flush()

local entries, win, col2 = detect_unread()
if not entries then
    io.write("检测失败: " .. tostring(win) .. "\n")
    os.exit(1)
end

-- 找文件传输助手
local ft_entry = find_file_transfer(entries, col2)
if not ft_entry then
    io.write("文件传输助手无未读消息\n")
    os.exit(0)
end

io.write(string.format("找到文件传输助手有未读 (条目 #%d)\n", ft_entry.idx)); io.flush()

-- 读取最新消息
io.write("读取最新消息...\n"); io.flush()
local message = read_latest_message(ft_entry, win)

if #message == 0 then
    io.write("未能读取消息内容\n")
    os.exit(1)
end

io.write("最新消息:\n" .. message:sub(1, 500) .. "\n\n"); io.flush()

-- 回复
io.write("回复中...\n"); io.flush()
local reply = reply_with_quote(message:sub(1, 200))  -- 只引用前200字

io.write("已回复: " .. reply:sub(1, 50) .. "...\n")
io.write("完成\n")
