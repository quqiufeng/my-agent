-- wechat-ocr/once.lua — 单次流程：发消息 / 读最后一条 / 转发大脑
-- 用法:
--   luajit once.lua send "文本"        # 第一步：发送到当前会话（文件传输助手）
--   luajit once.lua recv               # 第二步：读聊天框最后一条消息 → 转发大脑
--   luajit once.lua peek               # 只读最后一条，不转发（验收用）
--
-- 读消息用 ocr_capture_all（不依赖时间戳，第三列=聊天内容 x>win.w*0.30）

package.path = "/opt/my-agent/wechat-ocr/?.lua;/opt/my-agent/wechat-ocr/lua/?.lua;"
    .. "/opt/my-agent/wechat-ocr/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
    .. (package.path or "")
package.cpath = "/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;" .. (package.cpath or "")

local ffi = require("ffi")
local cjson = require("cjson")
ffi.cdef[[int usleep(unsigned int);]]

local D = "/opt/my-agent/wechat-ocr"
local AGENT_URL = os.getenv("AGENT_URL") or "http://localhost:4097"
local OPERATOR_DIR = os.getenv("OPERATOR_DIR") or "/opt/my-agent/operator"

local mode = arg[1] or "help"

-- ── 第一步：发送（点输入框 + 剪贴板粘贴，焦点稳） ───────────
if mode == "send" then
    local text = arg[2] or ""
    if text == "" then io.stderr:write("用法: once.lua send \"文本\"\n"); os.exit(2) end
    local ocr = require("wechat_ocr")
    local ok, err = ocr.init(D .. "/models/ch_PP-OCRv4_det_infer.onnx",
                             D .. "/models/ch_PP-OCRv4_rec_infer.onnx",
                             D .. "/ppocr_keys_v1.txt")
    if not ok then io.stderr:write("init 失败: " .. tostring(err) .. "\n"); os.exit(1) end
    os.execute("xdotool search --name 微信 windowactivate --sync 2>/dev/null")
    ffi.C.usleep(500000)
    local sent, serr = ocr.send(text)
    ocr.destroy()
    if not sent then io.stderr:write("发送失败: " .. tostring(serr) .. "\n"); os.exit(1) end
    print("已发送: " .. text)
    os.exit(0)
end

if mode ~= "recv" and mode ~= "peek" then
    io.stderr:write("用法: once.lua send \"文本\" | recv | peek\n")
    os.exit(2)
end

-- ── 读第三列最后一条消息 ─────────────────────────────────────
ffi.cdef[[
typedef struct ocr_engine_t ocr_engine_t;
ocr_engine_t* ocr_create(const char*, const char*, const char*);
char*         ocr_capture_all(ocr_engine_t*);
void          ocr_free_string(char*);
void          ocr_destroy(ocr_engine_t*);
]]

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(700000)

local lib = ffi.load(D .. "/lib/libwechat_ocr_core.so")
local e = lib.ocr_create(D .. "/models/ch_PP-OCRv4_det_infer.onnx",
                         D .. "/models/ch_PP-OCRv4_rec_infer.onnx",
                         D .. "/ppocr_keys_v1.txt")
if e == ffi.NULL then io.stderr:write("ocr_create 失败\n"); os.exit(1) end
local s = lib.ocr_capture_all(e)
if s == ffi.NULL then io.stderr:write("capture_all 失败\n"); lib.ocr_destroy(e); os.exit(1) end
local r = cjson.decode(ffi.string(s))
lib.ocr_free_string(s)
lib.ocr_destroy(e)

local win = r.win
local thresh = math.floor(win.w * 0.30)          -- 第三列（聊天内容）起点
local function is_ts(s)                            -- 时间戳/分隔
    return s:match("^%d%d?:%d%d$") or s == "昨天" or s == "今天"
        or s == "昨天" or s:match("星期") or s:match("^%d+月%d+日$")
end
local function clean(s)                            -- 去气泡边缘噪声（按整字符，避免字节级误伤）
    for _, ch in ipairs({ "」", "『", "』", "「", "《", "》", "（", "）" }) do
        s = s:gsub(ch, "")
    end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

-- 收集第三列消息框（排除标题栏 y<=40、时间戳）
local msgs = {}
for _, b in ipairs(r.boxes or {}) do
    if b.x >= thresh and b.y > 40 and not is_ts(b.text) then
        msgs[#msgs + 1] = b
    end
end

-- 去重：删掉被同一行更大框包含的小碎片（如长消息右侧多出的单字）
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
msgs = keep
table.sort(msgs, function(a, b) return a.y < b.y end)

-- 按 y 邻接分组：同一条消息若折成多行，行距约 30px；消息间距约 70px+
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

local last = groups[#groups] and clean(groups[#groups].text) or ""
if last == "" then io.stderr:write("第三列未读到消息\n"); os.exit(1) end
print("最后消息: " .. last)

if mode == "peek" then os.exit(0) end

-- ── 第二步：转发大脑（后台即发即走，不等模型跑完） ─────────
local function curl_capture(url, obj, timeout)
    local tmp = os.tmpname()
    local f = io.open(tmp, "w"); f:write(cjson.encode(obj)); f:close()
    local out = os.tmpname()
    os.execute(string.format(
        "curl -s --max-time %d -X POST -H 'Content-Type: application/json' --data-binary @%s '%s' > %s 2>/dev/null",
        timeout or 8, tmp, url, out))
    os.remove(tmp)
    local of = io.open(out, "r"); local body = of and of:read("*a") or ""
    if of then of:close() end
    os.remove(out)
    return body
end

local sess = curl_capture(AGENT_URL .. "/session?directory=" .. OPERATOR_DIR, {})
local sid = sess:match('"id":"(ses_[^"]+)"')
if not sid then io.stderr:write("创建大脑会话失败（opencode 未启动？）\n"); os.exit(1) end

local tmp = os.tmpname()
local f = io.open(tmp, "w")
f:write(cjson.encode({ parts = { { type = "text", text = "[微信输入] " .. last } } }))
f:close()
-- 后台发送：curl 完成后删除临时文件
os.execute(string.format(
    "sh -c 'curl -s --max-time 300 -X POST -H \"Content-Type: application/json\" --data-binary @%s \"%s/session/%s/message\" >/dev/null 2>&1; rm -f %s' >/dev/null 2>&1 &",
    tmp, AGENT_URL, sid, tmp))
print("已转发大脑: [微信输入] " .. last)

