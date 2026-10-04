-- wechat-ocr/lua/wechat_ocr/reader.lua
-- 读取微信第三列「最下面一条消息」，用 ocr_capture_all（不依赖时间戳）。
-- 供 once.lua / bridge.lua 共用。
local ffi = require("ffi")
local cjson = require("cjson")
ffi.cdef[[
typedef struct ocr_engine_t ocr_engine_t;
ocr_engine_t* ocr_create(const char*, const char*, const char*);
char*         ocr_capture_all(ocr_engine_t*);
void          ocr_free_string(char*);
void          ocr_destroy(ocr_engine_t*);
int           usleep(unsigned int);
]]

local M = {}
local lib, engine
local DIR = "/opt/my-agent/wechat-ocr"

function M.init(dir)
    if engine then return true end
    dir = dir or DIR
    local ok, l = pcall(ffi.load, dir .. "/lib/libwechat_ocr_core.so")
    if not ok then return false, "加载 libwechat_ocr_core.so 失败" end
    lib = l
    engine = lib.ocr_create(dir .. "/models/ch_PP-OCRv4_det_infer.onnx",
                            dir .. "/models/ch_PP-OCRv4_rec_infer.onnx",
                            dir .. "/ppocr_keys_v1.txt")
    if engine == nil or engine == ffi.NULL then return false, "ocr_create 失败" end
    return true
end

local function is_ts(s)
    return s:match("^%d%d?:%d%d$") or s == "昨天" or s == "今天"
        or s:match("星期") or s:match("^%d+月%d+日$")
end

local function clean(s) -- 整字符去气泡边缘噪声（避免 Lua 字节级字符类误伤中文）
    for _, ch in ipairs({ "」", "『", "』", "「", "《", "》", "（", "）" }) do
        s = s:gsub(ch, "")
    end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 返回最下面一条消息文本；activate=false 时不置顶窗口
function M.bottom(activate)
    if not engine then return nil, "未初始化" end
    if activate ~= false then
        os.execute("xdotool search --name 微信 windowactivate --sync 2>/dev/null")
        ffi.C.usleep(400000)
    end
    local s = lib.ocr_capture_all(engine)
    if s == nil or s == ffi.NULL then return nil, "capture_all 失败" end
    local r = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)

    local thresh = math.floor(r.win.w * 0.30) -- 第三列（聊天内容）起点
    local msgs = {}
    for _, b in ipairs(r.boxes or {}) do
        if b.x >= thresh and b.y > 40 and not is_ts(b.text) then
            msgs[#msgs + 1] = b
        end
    end
    -- 同行包含去重：删掉被更大框包住的小碎片
    local keep = {}
    for i, b in ipairs(msgs) do
        local dup = false
        for j, c in ipairs(msgs) do
            if i ~= j and math.abs(b.y - c.y) <= 15 and c.w > b.w
                and b.x >= c.x - 4 and (b.x + b.w) <= (c.x + c.w + 4) then
                dup = true; break
            end
        end
        if not dup then keep[#keep + 1] = b end
    end
    table.sort(keep, function(a, b) return a.y < b.y end)
    -- 按 y 邻接分组：一条消息折行则合并
    local groups = {}
    for _, b in ipairs(keep) do
        local g = groups[#groups]
        if g and (b.y - g.ylast) <= 45 then
            g.text = g.text .. b.text; g.ylast = b.y
        else
            groups[#groups + 1] = { text = b.text, ylast = b.y }
        end
    end
    return groups[#groups] and clean(groups[#groups].text) or ""
end

function M.close()
    if engine then lib.ocr_destroy(engine); engine = nil end
end

return M
