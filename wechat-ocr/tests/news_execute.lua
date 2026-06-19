#!/usr/bin/env luajit
-- news_execute.lua — 文件传输助手新消息 → 读取 → 回复
-- 检测未读 → 点进去 → 读最新消息 → 回复"收到！马上处理"+引用原文

local ffi = require("ffi")
local cjson = require("cjson")
ffi.cdef[[int usleep(unsigned int);]]
local badge = require("wechat_ocr.badge_detect")

-- 点击条目
local function click_entry(entry, win)
    local cx = win.x + entry.rx + entry.w / 2
    local cy = win.y + entry.ry + entry.h / 2
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", cx, cy))
    ffi.C.usleep(1500000)
end

-- 读取最新一条消息（消息区底部）
local function read_latest_message(win)
    -- 截取消息区底部（避开输入框，输入框在底部约 120px）
    local msg_x = win.x + math.floor(win.w * 0.40) + 20
    local msg_w = win.w - math.floor(win.w * 0.40) - 40
    local msg_y = win.y + win.h - 500  -- 底部往上 500px
    local msg_h = 380  -- 380px 高，到输入框上方
    os.execute(string.format("import -window root -crop %dx%d+%d+%d '/tmp/_ft_latest.png' 2>/dev/null", msg_w, msg_h, msg_x, msg_y))

    local lib = ffi.load("libwechat_ocr_core.so")
    ffi.cdef[[
        typedef struct ocr_engine_t ocr_engine_t;
        ocr_engine_t* ocr_create(const char*,const char*,const char*);
        char* ocr_capture_file(ocr_engine_t*, const char*, int, int);
        void ocr_free_string(char*);
        void ocr_destroy(ocr_engine_t*);
    ]]
    local e = lib.ocr_create("/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_det_infer.onnx",
                              "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_rec_infer.onnx",
                              "/opt/my-agent/wechat-ocr/ppocr_keys_v1.txt")
    local s = lib.ocr_capture_file(e, "/tmp/_ft_latest.png", msg_x, msg_y)
    lib.ocr_destroy(e)
    if not s or s == ffi.NULL then return "" end
    local d = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)

    -- 从 OCR 结果中找最靠下的文字（最新消息）
    local latest_box = nil
    for _, b in ipairs(d.boxes or {}) do
        if #b.text > 2 then
            if not latest_box or b.y + b.h > latest_box.y + latest_box.h then
                latest_box = b
            end
        end
    end
    return latest_box and latest_box.text or ""
end

-- 回复（粘贴+发送）
local function reply(content)
    local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
    local wx = tonumber(geo:match("Position: (%d+)"))
    local wy = tonumber(geo:match(",(%d+)"))
    local ww = tonumber(geo:match("Geometry: (%d+)"))
    local wh = tonumber(geo:match("x(%d+)"))

    -- 点输入框
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + ww - 200, wy + wh - 80))
    ffi.C.usleep(500000)

    -- 剪贴板写入
    local f = io.open("/tmp/_ft_reply.txt", "w")
    if f then f:write(content); f:close() end
    os.execute("xclip -selection clipboard < /tmp/_ft_reply.txt 2>/dev/null")
    ffi.C.usleep(200000)
    os.execute("xdotool key ctrl+v 2>/dev/null")
    ffi.C.usleep(300000)
    os.execute("xdotool key Return 2>/dev/null")
end

-- ===== 主流程 =====
io.write("检测中...\n"); io.flush()

local result = badge.detect()
if not result then io.write("检测失败\n"); os.exit(1) end

local ft_entry = badge.find_file_transfer(result)
if not ft_entry then io.write("未找到文件传输助手\n"); os.exit(0) end

if not ft_entry.found then
    io.write("文件传输助手无未读消息\n")
    os.exit(0)
end

io.write("有未读消息，打开...\n"); io.flush()
click_entry(ft_entry, result.win)

-- 滚到底部看最新消息
os.execute("xdotool key End 2>/dev/null")
ffi.C.usleep(1000000)

io.write("读取最新消息...\n"); io.flush()
local msg = read_latest_message(result.win)
if #msg == 0 then io.write("未能读取消息\n"); os.exit(1) end

io.write("最新消息:\n" .. msg:sub(1, 300) .. "\n\n"); io.flush()

-- 构造回复
local reply_text = "收到！马上处理\n\n—— 原文：\n" .. msg:sub(1, 200)

io.write("回复中...\n"); io.flush()
reply(reply_text)

io.write("已完成\n")
