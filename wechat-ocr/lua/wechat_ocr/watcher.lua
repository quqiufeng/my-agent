-- wechat-ocr/lua/wechat_ocr/watcher.lua
-- 微信新消息监控（供 bridge.lua 常驻轮询使用，quiet 模式）
--
-- 只做后台读取，不聚焦/不点击微信：
--   window_capture(): import -window <xid> 抓微信窗口（遮挡可读；最小化会失败）
--   ocr():           对截图跑 PP-OCRv4
--   find_row():      在第二列按会话名找行（容忍 OCR 错字）
--   read_preview():  读该行下方预览文字（=最新一条消息）
local ffi = require("ffi")
local cjson = require("cjson")

ffi.cdef[[
typedef struct ocr_engine_t ocr_engine_t;
ocr_engine_t* ocr_create(const char*, const char*, const char*);
char*         ocr_capture_file(ocr_engine_t*, const char*, int, int);
void          ocr_free_string(char*);
void          ocr_destroy(ocr_engine_t*);
int           usleep(unsigned int);
int           getpid(void);
]]

local M = {}
local DIR = os.getenv("WECHAT_DIR") or "/opt/my-agent/wechat-ocr"
local PID = ffi.C.getpid()
local SHOT = string.format("/tmp/wx_watch_%d.png", PID)

local lib, engine

local function sh(cmd) os.execute(cmd .. " >/dev/null 2>&1") end

local function popen_line(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return nil end
    local out = f:read("*a"); f:close()
    return out
end

-- ── 初始化 ──────────────────────────────────────────────────
function M.init()
    if engine then return true end
    local ok, l = pcall(ffi.load, DIR .. "/lib/libwechat_ocr_core.so")
    if not ok then ok, l = pcall(ffi.load, "libwechat_ocr_core.so") end
    if not ok then return false, "加载 libwechat_ocr_core.so 失败" end
    lib = l
    engine = lib.ocr_create(DIR .. "/models/ch_PP-OCRv4_det_infer.onnx",
                            DIR .. "/models/ch_PP-OCRv4_rec_infer.onnx",
                            DIR .. "/ppocr_keys_v1.txt")
    if engine == nil or engine == ffi.NULL then return false, "ocr_create 失败" end
    return true
end

function M.close()
    if engine and engine ~= ffi.NULL then lib.ocr_destroy(engine) end
    engine = nil
    os.remove(SHOT)
end

-- ── 窗口 / 截图 ─────────────────────────────────────────────

-- 取面积最大的名为「微信」的窗口 id 与几何
function M.window()
    local out = popen_line("xdotool search --name 微信") or ""
    local best_id, best_area, bx, by, bw, bh
    for id in out:gmatch("%d+") do
        local geo = popen_line("xdotool getwindowgeometry " .. id) or ""
        local x = tonumber(geo:match("Position: (%d+)"))
        local y = tonumber(geo:match(",(%d+)"))
        local w = tonumber(geo:match("Geometry: (%d+)"))
        local h = tonumber(geo:match("x(%d+)"))
        if x and y and w and h and w * h > (best_area or 0) then
            best_id, best_area, bx, by, bw, bh = id, w * h, x, y, w, h
        end
    end
    if not best_id then return nil end
    return { id = best_id, x = bx, y = by, w = bw, h = bh }
end

-- 后台抓微信窗口（import -window，遮挡也可读，不抢焦点）
function M.window_capture()
    local win = M.window()
    if not win then return nil, "未找到微信窗口" end
    sh(string.format("import -window %s '%s'", win.id, SHOT))
    local f = io.open(SHOT, "rb")
    if not f then return nil, "窗口截图失败(可能已最小化)" end
    f:close()
    return SHOT, win
end

-- 对截图 OCR，返回 {win=..., boxes={x,y(窗口坐标),w,h,text}}
-- 注意 ocr_capture_file 从 y=35 起裁，box.y 是相对裁剪的，这里补回 35。
function M.ocr(shot, win)
    local s = lib.ocr_capture_file(engine, shot, win.x, win.y)
    if s == nil or s == ffi.NULL then return nil, "OCR 失败" end
    local d = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)
    local boxes = {}
    for _, b in ipairs(d.boxes or {}) do
        boxes[#boxes + 1] = { x = b.x, y = b.y + 35, w = b.w, h = b.h, text = b.text }
    end
    return { win = win, boxes = boxes }
end

-- ── 定位会话行 / 读预览 ─────────────────────────────────────

-- 名称模糊匹配：整串包含，或名字中任意相邻两字出现在 OCR 文本里
-- （容忍 OCR 错字，如「文件传输助手」被读成「生传输助丰」）
local function utf8_chars(s)
    local t = {}
    for ch in s:gmatch("[\1-\127\194-\244][\128-\191]*") do t[#t + 1] = ch end
    return t
end

local function name_match(text, name)
    local t = (text or ""):gsub("%s", "")
    local n = (name or ""):gsub("%s", "")
    if n == "" then return false end
    if t == n or t:find(n, 1, true) or n:find(t, 1, true) then return true end
    local chars = utf8_chars(n)
    for i = 1, #chars - 1 do
        if t:find(chars[i] .. chars[i + 1], 1, true) then return true end
    end
    return false
end

-- 在 OCR 结果里找第二列指定会话名的行（窗口坐标）
function M.find_row(res, name)
    local col2_max = res.win.w * 0.24
    for _, b in ipairs(res.boxes) do
        if b.x < col2_max and b.y > 50 and name_match(b.text, name) then
            return b
        end
    end
    return nil
end

-- 读该行下方预览文字（=最新一条消息），只读第二列、不点开会话
function M.read_preview(shot, win, row)
    if not shot or not row then return nil, "缺行/截图" end
    -- 左边界留足：预览可能以 # 标签开头，别把 # 切掉
    local x = math.max(0, row.x - 100)
    local y = row.y + row.h          -- 名字下方那一行 = 预览
    local w = math.min(win.w - x, 560)
    local h = 46
    local crop = string.format("/tmp/wx_prev_%d.png", PID)
    sh(string.format("convert '%s' +repage -crop %dx%d+%d+%d +repage -resize 400%% -sharpen 0x1.5 '%s'",
        shot, w, h, x, y, crop))
    local s = lib.ocr_capture_file(engine, crop, 0, 0)
    os.remove(crop)
    if s == nil or s == ffi.NULL then return nil, "预览 OCR 失败" end
    local d = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)
    local boxes = d.boxes or {}
    if #boxes == 0 then return nil, "预览为空" end
    table.sort(boxes, function(a, b) return a.x < b.x end)
    local parts = {}
    for _, b in ipairs(boxes) do
        if not b.text:find("传输") then parts[#parts + 1] = b.text end
    end
    local s2 = table.concat(parts, "")
    s2 = s2:gsub("^%s+", ""):gsub("%s+$", "")
    if s2 == "" then return nil, "只有标题无预览" end
    return s2
end

return M
