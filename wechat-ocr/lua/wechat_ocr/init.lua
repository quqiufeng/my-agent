-- WeChat OCR Library
-- 通过 LuaJIT FFI 调用 C++ OCR 引擎，实现桌面微信的识别和操作
-- ============================================================
-- 微信窗口结构 (横向三竖状区域)
-- ============================================================
--
--  ┌──────┬─────────────────────┬──────────────────────────┐
--  │ 第一 │ 第二                │ 第三                     │
--  │      │                     │                          │
--  │ 图标 │  列表显示区域        │  内容展示区              │
--  │ 功能 │                     │  (当前选中项的展示面板)  │
--  │ 区域 │  显示:               │                          │
--  │      │  · 聊天列表         │  标题/名称栏             │
--  │      │  · 公众号           │  ──────────────────     │
--  │      │  · 服务号           │                          │
--  │      │  · 微信支付         │  聊天消息 / 内容         │
--  │      │  · 文件传输助手     │  (消息/文章/账单等)      │
--  │      │  · 群聊 / 单聊      │                          │
--  │      │  · 收藏等           │                          │
--  │      │                     │  ──────────────────     │
--  │      │  选中项有灰色高亮块  │  输入框                  │
--  └──────┴─────────────────────┴──────────────────────────┘
-- ============================================================

local ffi = require("ffi")
local cjson = require("cjson")

-- ======== C API bindings ========
ffi.cdef[[
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*, const char*, const char*);
    char*         ocr_capture(ocr_engine_t*);
    void          ocr_free_string(char*);
    void          ocr_destroy(ocr_engine_t*);
    const char*   ocr_last_error(ocr_engine_t*);
    char*         ocr_get_input_box(ocr_engine_t*);
    char*         ocr_find_taskbar_icon(ocr_engine_t*);
    void          usleep(unsigned int);
    int           getpid(void);
]]

local lib
local ok, err = pcall(function()
    lib = ffi.load("libwechat_ocr_core.so")
end)
if not ok then
    lib = ffi.load("/opt/my-agent/wechat-ocr/lib/libwechat_ocr_core.so")
end

-- ======== Internal state ========
local M = {}
local engine = nil
local prev_text = ""
local cycle = 0
local stop_requested = false
local PID = ffi.C.getpid()
local CHAR_TMP = string.format("/tmp/wechat_char_%d.txt", PID)
local SEND_TMP = string.format("/tmp/wechat_send_path_%d.txt", PID)

-- 外部可调用 M.stop() 结束 monitor 循环
function M.stop() stop_requested = true end

-- ======== Public API ========

-- Initialize OCR engine
function M.init(det_model, rec_model, dict_path)
    if engine then M.destroy() end
    local h = lib.ocr_create(det_model, rec_model, dict_path)
    if h == nil or h == ffi.NULL then return false, "ocr_create failed" end
    engine = h
    return true
end

function M.destroy()
    if engine and engine ~= ffi.NULL then lib.ocr_destroy(engine) end
    engine = nil; prev_text = ""; cycle = 0
end

-- Raw capture (C层裁剪，40%+10px)
function M.capture_raw()
    if not engine then return nil, "engine not initialized" end
    local c_str = lib.ocr_capture(engine)
    if c_str == nil or c_str == ffi.NULL then
        return nil, ffi.string(lib.ocr_last_error(engine))
    end
    local json_str = ffi.string(c_str)
    lib.ocr_free_string(c_str)
    local ok, data = pcall(cjson.decode, json_str)
    if not ok then return nil, "json parse: " .. tostring(data) end
    return data
end

-- 时间戳模式：全窗口扫描，通过时间戳定位第三列
-- 返回第三列的文字内容
function M.capture_third_column()
    if not engine then return nil, "engine not initialized" end
    
    -- 获取全窗口数据（临时改crop有点难，用另一种方式）
    -- 直接取原始捕获结果中用时间戳过滤
    local data, err = M.capture_raw()
    if not data then return nil, err end
    
    local boxes = data.boxes or {}
    if #boxes == 0 then return "" end
    
    -- 找时间戳（格式 HH:MM，或 "昨天"/"今天"）
    local ts_x = {}
    for _, b in ipairs(boxes) do
        if b.text:match("%d%d:%d%d") or b.text == "昨天" or b.text == "今天" then
            local cx = b.x + b.w / 2
            table.insert(ts_x, cx)
        end
    end
    
    -- 用时间戳中位数 + 20px 作为分界
    local boundary = 0
    if #ts_x > 0 then
        table.sort(ts_x)
        local mid_idx = math.ceil(#ts_x / 2)
        local mid = ts_x[mid_idx]
        boundary = mid + 20
    else
        -- 没有时间戳，用默认
        boundary = data.win.w * 0.40 + 10
    end
    
    -- 过滤保留第三列的文字
    local lines = {}
    for _, b in ipairs(boxes) do
        local cx = b.x + b.w / 2
        local cy = b.y + b.h / 2
        if cx >= boundary then
            table.insert(lines, b.text)
        end
    end
    
    return table.concat(lines, "\n")
end

-- 默认 capture 使用时间戳过滤
function M.capture()
    return M.capture_third_column()
end

-- 发送消息（逐字粘贴）
function M.send(text)
    if not engine then return false, "engine not initialized" end
    if not text or text == "" then return false, "empty text" end

    local c_str = lib.ocr_get_input_box(engine)
    if c_str == nil or c_str == ffi.NULL then
        return false, ffi.string(lib.ocr_last_error(engine))
    end
    local json_str = ffi.string(c_str)
    lib.ocr_free_string(c_str)
    local ok, box = pcall(cjson.decode, json_str)
    if not ok then return false, "json: " .. tostring(box) end

    local cx = box.x + box.w / 2
    local cy = box.y + box.h / 2
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", math.floor(cx), math.floor(cy)))
    ffi.C.usleep(200000)

    -- 逐字粘贴（UTF-8）
    local i = 1
    while i <= #text do
        local byte = text:byte(i)
        local char_len = 1
        if byte >= 240 then char_len = 4
        elseif byte >= 224 then char_len = 3
        elseif byte >= 128 then char_len = 2 end
        local ch = text:sub(i, i + char_len - 1)
        i = i + char_len

        local f = io.open(CHAR_TMP, "w")
        if f then f:write(ch); f:close() end
        os.execute("xclip -selection clipboard " .. CHAR_TMP .. " </dev/null >/dev/null 2>&1")
        ffi.C.usleep(50000)
        os.execute("xdotool key ctrl+v 2>/dev/null")
        local delay = 80 + math.random(170)
        ffi.C.usleep(delay * 1000)
    end
    ffi.C.usleep(150000)
    os.execute("xdotool key Return 2>/dev/null")
    return true
end

-- 发送文件
function M.send_file(filepath)
    if not filepath or filepath == "" then return false, "no file path" end
    local c_str = lib.ocr_get_input_box(engine)
    if c_str == nil or c_str == ffi.NULL then return false, "cannot locate" end
    local json_str = ffi.string(c_str)
    lib.ocr_free_string(c_str)
    local ok, box = pcall(cjson.decode, json_str)
    if not ok then return false, "json: " .. tostring(box) end
    
    local ix = box.x - 80
    local iy = box.y - 30
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", math.floor(ix), math.floor(iy)))
    ffi.C.usleep(800000)
    
    local f = io.open(SEND_TMP, "w")
    if f then f:write(filepath); f:close() end
    os.execute("xclip -selection clipboard " .. SEND_TMP .. " </dev/null >/dev/null 2>&1")
    ffi.C.usleep(100000)
    os.execute("xdotool key ctrl+v 2>/dev/null")
    ffi.C.usleep(500000)
    os.execute("xdotool key Return 2>/dev/null")
    ffi.C.usleep(2000000)
    os.execute("xdotool key Return 2>/dev/null")
    return true
end

-- 打开微信
function M.open(wait_ms)
    wait_ms = wait_ms or 2000
    local c_str = lib.ocr_find_taskbar_icon(nil)
    if c_str == nil or c_str == ffi.NULL then
        os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
        ffi.C.usleep(wait_ms * 1000)
        return true
    end
    local json_str = ffi.string(c_str)
    lib.ocr_free_string(c_str)
    local ok, icon = pcall(cjson.decode, json_str)
    if not ok then return false, "json: " .. tostring(icon) end
    local cx = icon.x + icon.w / 2
    local cy = icon.y + icon.h / 2
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", cx, cy))
    ffi.C.usleep(wait_ms * 1000)
    return true
end

-- 监控
function M.monitor(opts)
    opts = opts or {}
    local interval = opts.interval_ms or 3000
    local on_msg = opts.on_message
    local on_init = opts.on_initial
    local on_err = opts.on_error or function(e)
        io.stderr:write("[ocr] " .. tostring(e) .. "\n")
    end
    prev_text = ""; cycle = 0; stop_requested = false
    while not stop_requested do
        local t0 = os.clock()
        local text, err = M.capture()
        if text then
            if text ~= "" and text ~= prev_text then
                cycle = cycle + 1
                if prev_text == "" then
                    if on_init then on_init(text) end
                else
                    local common = 0
                    local m = math.min(#prev_text, #text)
                    while common < m and
                          prev_text:byte(common+1) == text:byte(common+1) do
                        common = common + 1
                    end
                    if common < #text then
                        local new = text:sub(common+1)
                        new = new:match("^[\n\r]*(.*)") or new
                        if #new > 3 and on_msg then on_msg(new, cycle) end
                    end
                end
                prev_text = text
            end
        else
            if on_err then on_err(err or "unknown") end
        end
        local elapsed = (os.clock() - t0) * 1000
        local sleep = math.max(100, interval - math.floor(elapsed))
        ffi.C.usleep(sleep * 1000)
    end
end

function M.start(model_dir)
    model_dir = model_dir or "/opt/my-agent/wechat-ocr/"
    local ok, err = M.init(
        model_dir .. "models/ch_PP-OCRv4_det_infer.onnx",
        model_dir .. "models/ch_PP-OCRv4_rec_infer.onnx",
        model_dir .. "ppocr_keys_v1.txt")
    if not ok then io.stderr:write("FATAL: " .. tostring(err) .. "\n"); os.exit(1) end
    io.write("[wechat_ocr] Monitoring... (Ctrl+C to stop)\n"); io.flush()
    M.monitor({
        on_initial = function(text) io.write("[Initial]\n" .. text .. "\n"); io.flush() end,
        on_message = function(text, cycle)
            io.write("[New] cycle=" .. cycle .. "\n" .. text .. "\n---\n"); io.flush()
        end,
    })
end

return M
