-- wechat-ocr/lua/wechat_ocr/watcher.lua
-- 微信新消息监控（供 bridge.lua 常驻轮询使用）
--
-- 流程：点状态栏微信图标 → 抓微信窗口 → OCR 第二列找「文件传输助手」行
--       → 该行有红点才判定有新消息（双重认证）→ 打开会话读新消息 → 转发大脑。
--
-- 关键点：窗口截图用 `import -window <xid>`（微信被遮挡也能读到内容），
--         红点检测在后台完成，只有确认「文件传输助手」有新消息才真正操作窗口。
local ffi = require("ffi")
local cjson = require("cjson")

ffi.cdef[[
typedef struct ocr_engine_t ocr_engine_t;
ocr_engine_t* ocr_create(const char*, const char*, const char*);
char*         ocr_capture_file(ocr_engine_t*, const char*, int, int);
char*         ocr_find_taskbar_icon(ocr_engine_t*);
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
local function sleep_us(us) ffi.C.usleep(us) end

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
    if not ok then
        ok, l = pcall(ffi.load, "libwechat_ocr_core.so")
    end
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

-- ── 窗口 ────────────────────────────────────────────────────

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

-- 最大化为整屏（微信默认最大化，这里幂等保证）
function M.ensure_maximized(win)
    local sw, sh = 2560, 1440
    local d = popen_line("xdotool getdisplaygeometry") or ""
    local w, h = d:match("(%d+)%s+(%d+)")
    if w then sw, sh = tonumber(w), tonumber(h) end
    if win and (win.w < sw - 40 or win.h < sh - 80) then
        sh("wmctrl -i -r 0x" .. string.format("%x", tonumber(win.id)) ..
           " -b add,maximized_vert,maximized_horz")
        sleep_us(700000)
    end
end

-- 底栏截屏里找微信绿图标（#07C160），返回中心坐标
local function taskbar_icon_im()
    local sw, sh_h = 2560, 1440
    local d = popen_line("xdotool getdisplaygeometry") or ""
    local a, b = d:match("(%d+)%s+(%d+)")
    if a then sw, sh_h = tonumber(a), tonumber(b) end
    local bh = 64
    local bar = string.format("/tmp/wx_bar_%d.png", PID)
    sh(string.format("import -window root -crop %dx%d+0+%d +repage '%s'", sw, bh, sh_h - bh, bar))
    local out = popen_line(string.format(
        "convert '%s' -fuzz 22%% -fill white -opaque '#07c160' -fill black +opaque white "
        .. "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1", bar))
    os.remove(bar)
    local best, best_area = nil, 0
    for line in out:gmatch("[^\n]+") do
        local id, w, h, x, y, area = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
        if w then
            local nw, nh, nx, ny, na = tonumber(w), tonumber(h), tonumber(x), tonumber(y), tonumber(area)
            if nx > sw * 0.88 and na >= 120 and na <= 3000 and nw >= 8 and nh >= 8 and na > best_area then
                best_area = na
                best = { x = nx + nw / 2, y = (sh_h - bh) + ny + nh / 2 }
            end
        end
    end
    if best then return best.x, best.y end
    return nil
end

-- 找到状态栏微信图标（绿色），返回中心坐标
local function taskbar_icon()
    if engine then
        local s = lib.ocr_find_taskbar_icon(engine)
        if s ~= nil and s ~= ffi.NULL then
            local icon = cjson.decode(ffi.string(s))
            lib.ocr_free_string(s)
            if icon and icon.x then
                return icon.x + (icon.w or 0) / 2, icon.y + (icon.h or 0) / 2
            end
        end
    end
    return taskbar_icon_im()
end

-- 当前活动窗口 id
function M.active_window()
    local out = popen_line("xdotool getactivewindow") or ""
    return tonumber(out:match("(%d+)"))
end

-- 点状态栏微信图标，让微信独占显示（最大化到前台）
function M.focus()
    if not M._prev_win then
        local cur = M.active_window()
        if cur then
            local name = popen_line("xdotool getwindowname " .. cur) or ""
            if not name:find("微信") then M._prev_win = cur end
        end
    end
    local cx, cy = taskbar_icon()
    if cx then
        sh(string.format("xdotool mousemove %d %d click 1", cx, cy))
        sleep_us(900000)
    end
    -- 兜底：直接激活窗口
    sh("xdotool search --name 微信 windowactivate --sync")
    sleep_us(400000)
    M.ensure_maximized(M.window())
end

-- 让微信失去焦点：恢复到聚焦前的窗口（保持微信可见，便于后台查红点）
function M.unfocus()
    if M._prev_win then
        sh(string.format("xdotool windowactivate %d", M._prev_win))
        M._prev_win = nil
        sleep_us(300000)
    end
end

-- 抓微信窗口（前置后截取屏幕对应区域），返回截图路径、窗口几何
-- 注意：不能对微信用 `import -window <xid>`：会话区是独立子窗口，
-- 直接抓 XID 会得到空白会话区，必须按屏幕区域截。
function M.capture()
    local win = M.window()
    if not win then return nil, "未找到微信窗口" end
    sh(string.format("import -window root -crop %dx%d+%d+%d +repage '%s'",
        win.w, win.h, win.x, win.y, SHOT))
    local f = io.open(SHOT, "rb")
    if not f then return nil, "截图失败" end
    f:close()
    return SHOT, win
end

-- 后台抓微信窗口（import -window，遮挡也可读，不抢焦点）。
-- 只用于「查红点」；会话区是 GPU 子窗，抓 XID 会空白，故读消息仍需 focus 后屏幕截图。
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

-- ── 判定 ────────────────────────────────────────────────────

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

-- 兼容旧接口
function M.find_filehelper(res)
    return M.find_row(res, "文件传输助手")
end

-- 该行是否有未读红点（红点列表由 red_badges 一次性算出）
function M.row_has_badge(row, badges)
    local cy = row.y + row.h / 2
    for _, b in ipairs(badges) do
        if math.abs((b.y + b.h / 2) - cy) <= 45 then return true end
    end
    return false
end

-- 在第二列找红点（窗口坐标）。红点一般在头像右上角，x∈[80,180]，尺寸 5~22px。
function M.red_badges(shot, win)
    local col2_w = math.floor(win.w * 0.24)
    local cmd = string.format(
        "convert '%s' +repage -crop %dx%d+0+0 +repage "
        .. "-fx '(r>0.78&&g<0.47&&b<0.47)?1:0' "
        .. "-define connected-components:verbose=true -connected-components 4 /dev/null 2>&1 "
        .. "| grep -v 'bgcolor\\|id:\\|0:.*gray'",
        shot, col2_w, win.h)
    local f = io.popen(cmd)
    local out = f and f:read("*a") or ""
    if f then f:close() end
    local badges = {}
    for line in out:gmatch("[^\n]+") do
        local id, bw, bh, bx, by, area = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
        if bw then
            local nw, nh, nx, ny, na = tonumber(bw), tonumber(bh), tonumber(bx), tonumber(by), tonumber(area)
            local ratio = math.max(nw / nh, nh / nw)
            if na >= 8 and na <= 400 and nw >= 4 and nh >= 4 and ratio <= 3
                and nx >= 80 and (nx + nw) <= 180 then
                badges[#badges + 1] = { x = nx, y = ny, w = nw, h = nh, area = na }
            end
        end
    end
    return badges
end

-- 双重认证：文件传输助手行存在，且该行有红点
function M.filehelper_has_unread(shot, win, res)
    local row = M.find_filehelper(res)
    if not row then return false, nil end
    local badges = M.red_badges(shot, win)
    local row_cy = row.y + row.h / 2
    for _, b in ipairs(badges) do
        local cy = b.y + b.h / 2
        if math.abs(cy - row_cy) <= 45 then
            return true, row
        end
    end
    return false, row
end

-- 往当前焦点输入框粘贴文本（中文用剪贴板）
local function type_text(text)
    local tmp = string.format("/tmp/wx_type_%d.txt", PID)
    local f = io.open(tmp, "w"); f:write(text); f:close()
    sh("xclip -selection clipboard " .. tmp .. " </dev/null")
    sleep_us(80000)
    sh("xdotool key --clearmodifiers ctrl+a")
    sleep_us(60000)
    sh("xdotool key --clearmodifiers Delete")
    sleep_us(60000)
    sh("xdotool key --clearmodifiers ctrl+v")
    sleep_us(250000)
    os.remove(tmp)
end

-- 第二列顶部搜索框里搜「文件传输助手」（行不可见时用）
function M.search_filehelper(win)
    local sx = win.x + math.floor(win.w * 0.10)
    local sy = win.y + 45
    sh(string.format("xdotool mousemove %d %d click 1", sx, sy))
    sleep_us(500000)
    type_text("文件传输助手")
    sleep_us(400000)
    sh("xdotool key Return")
    sleep_us(1200000)
end

-- 读「文件传输助手」行下方那一行的预览文字（=最新一条消息），
-- 只读第二列、不点开会话，红点保留。
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
    -- 同一行按 x 拼接（消息可能被切成多个框）
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

-- 点开「文件传输助手」行；row 为空则用第二列搜索框搜「文件传输助手」进入
function M.open_filehelper(row, win)
    if row then
        local sx = win.x + math.floor(win.w * 0.10)
        local sy = win.y + row.y + row.h / 2
        sh(string.format("xdotool mousemove %d %d click 1", sx, sy))
    else
        M.search_filehelper(win)   -- 搜索并回车，通常直接进入会话
    end
    sleep_us(900000)
    return true
end

-- ── 读取新消息 ──────────────────────────────────────────────

local function is_ts(s)
    return s:match("^%d%d?:%d%d$") or s == "昨天" or s == "今天"
        or s:find("星期") or s:match("^%d+月%d+日$")
end

-- 打开会话后，读第三列最新一条消息。
-- 会话区是 GPU 渲染，点击该行后短时间内容才可被抓到，故抓不到就重试。
function M.read_newest_incoming(win, tries)
    tries = tries or 5
    for _ = 1, tries do
        local shot, w = M.capture()
        if shot then
            local res = M.ocr(shot, w)
            local ww = w.w
            local col3 = ww * 0.30

            local msgs = {}
            for _, b in ipairs(res.boxes) do
                if b.x >= col3 and b.y > 60 and not is_ts(b.text) then
                    msgs[#msgs + 1] = b
                end
            end
            if #msgs > 0 then
                return M._bottom_text(msgs, ww)
            end
        end
        sleep_us(400000)
    end
    return nil, "第三列无消息"
end

-- 从已有 OCR 结果里读第三列最下面一条消息（=会话里最新气泡）
function M.read_bottom_from(res, win)
    if not res or not win then return nil end
    local col3 = win.w * 0.30
    local msgs = {}
    for _, b in ipairs(res.boxes) do
        if b.x >= col3 and b.y > 60 and not is_ts(b.text) then
            msgs[#msgs + 1] = b
        end
    end
    if #msgs == 0 then return nil end
    return M._bottom_text(msgs, win.w)
end

function M._bottom_text(msgs, ww)
    -- 按 y 邻接分组（折行合并）
    table.sort(msgs, function(a, b) return a.y < b.y end)
    local groups = {}
    for _, b in ipairs(msgs) do
        local g = groups[#groups]
        if g and (b.y - g.ylast) <= 45 then
            g.text = g.text .. b.text
            g.ylast = b.y
        else
            groups[#groups + 1] = { text = b.text, ylast = b.y }
        end
    end

    -- 触发时（文件传输助手有未读）最下面一条即为新收到的消息；
    -- 自己刚发的回复不会产生未读，且此时尚未回程，故最底部一定是对方消息。
    local g = groups[#groups]
    if not g then return nil, "无消息" end
    return (g.text:gsub("^%s+", ""):gsub("%s+$", ""))
end

return M
