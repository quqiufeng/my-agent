-- badge_detect.lua — 微信第二列红点检测公共模块
-- 被 test_avatar_badges.lua 和 news_execute.lua 复用

local ffi = require("ffi")
local cjson = require("cjson")
ffi.cdef[[int usleep(unsigned int); int getpid(void);]]

local dir = "/opt/my-agent/wechat-ocr"
local PID = ffi.C.getpid()
local SHOT = string.format("/tmp/wechat_badge_%d.png", PID)
local RED  = string.format("/tmp/_bd_red_%d.png", PID)

-- 加载 OCR 库
local lib = ffi.load("libwechat_ocr_core.so")
ffi.cdef[[
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*,const char*,const char*);
    char* ocr_capture_file(ocr_engine_t*, const char*, int, int);
    void ocr_free_string(char*);
    void ocr_destroy(ocr_engine_t*);
]]

local M = {}

-- 检测：返回 { entries, red_dots, col2, win, shot }
-- entries: {rx, ry, w, h, idx, found, dot_x, dot_y, from_text}
-- red_dots: {x, y, w, h, px}
-- col2: 第二列 OCR 文字框
function M.detect()
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    ffi.C.usleep(500000)

    local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
    local win_x = tonumber(geo:match("Position: (%d+)"))
    local win_y = tonumber(geo:match(",(%d+)"))
    local win_w = tonumber(geo:match("Geometry: (%d+)"))
    local win_h = tonumber(geo:match("x(%d+)"))
    if not win_w then return nil, "无法获取窗口" end

    -- 截图
    local shot = SHOT
    os.execute(string.format("import -window root -crop %dx%d+%d+%d '%s' 2>/dev/null", win_w, win_h, win_x, win_y, shot))

    -- OCR
    local e = lib.ocr_create(dir.."/models/ch_PP-OCRv4_det_infer.onnx",
                              dir.."/models/ch_PP-OCRv4_rec_infer.onnx",
                              dir.."/ppocr_keys_v1.txt")
    local s = lib.ocr_capture_file(e, shot, win_x, win_y)
    lib.ocr_destroy(e)
    if not s or s == ffi.NULL then return nil, "OCR失败" end

    local d = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)
    local boxes = d.boxes or {}

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

    -- 找第一个条目
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

    -- 连通分量分析
    os.execute(string.format("convert '%s' +repage -fx '(r>g*2.2&&r>b*2.2&&r>0.7&&g<0.5)?1:0' '%s' 2>/dev/null", shot, RED))
    local pipe_cc = io.popen("convert '" .. RED .. "' -define connected-components:verbose=true -connected-components 4 /dev/null 2>/dev/null | grep -v 'bgcolor\\|id:\\|0:'")
    local cc_output = pipe_cc:read("*a"); pipe_cc:close()

    local red_dots = {}
    for line in cc_output:gmatch("[^\n]+") do
        local id, w, h, x, y, px = line:match("(%d+):%s*(%d+)x(%d+)%+(%d+)%+(%d+)%s+[%d.]+,[%d.]+%s+(%d+)")
        if w and h and x and y and px then
            local nw, nh, nx, ny, np = tonumber(w), tonumber(h), tonumber(x), tonumber(y), tonumber(px)
            if nw >= 5 and nh >= 5 and nw <= 20 and nh <= 20 and nx < 200 and np >= 20 then
                table.insert(red_dots, {x=nx, y=ny, w=nw, h=nh, px=np})
            end
        end
    end

    -- 匹配红点到条目
    for _, dot in ipairs(red_dots) do
        local cy = dot.y + dot.h / 2
        for _, entry in ipairs(entries) do
            if cy >= entry.ry - 60 and cy <= entry.ry + entry.h + 10 then
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

    -- "*条" 文本匹配
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

    return {entries=entries, red_dots=red_dots, col2=col2, win={x=win_x, y=win_y, w=win_w, h=win_h}, shot=shot}
end

-- 找文件传输助手条目（搜索全部 col2，不限条目范围）
function M.find_file_transfer(result)
    -- 先找"文件传输"文字的精确位置
    local ft_ry = nil
    for _, b in ipairs(result.col2) do
        if b.text:find("文件传输") or b.text:find("文件传输") then
            ft_ry = b.ry
            break
        end
    end
    if not ft_ry then return nil end

    -- 找到最接近该文字位置的条目
    local best_entry, best_dist = nil, 999
    for _, entry in ipairs(result.entries) do
        local dist = math.abs(entry.ry + entry.h / 2 - ft_ry)
        if dist < best_dist then
            best_dist = dist
            best_entry = entry
        end
    end
    return best_entry
end

return M
