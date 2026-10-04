-- wechat-ocr/once.lua — 单次流程：发消息 / 读最下面一条 / 转发大脑
-- 用法:
--   luajit once.lua send "文本"        # 第一步：发送到当前会话（文件传输助手）
--   luajit once.lua recv               # 第二步：读最下面一条消息 → 转发大脑
--   luajit once.lua peek               # 只读最下面一条，不转发（验收用）

package.path = "/opt/my-agent/wechat-ocr/?.lua;/opt/my-agent/wechat-ocr/lua/?.lua;"
    .. "/opt/my-agent/wechat-ocr/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
    .. (package.path or "")
package.cpath = "/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;" .. (package.cpath or "")

local ffi = require("ffi")
local cjson = require("cjson")
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

-- ── 读最下面一条消息 ─────────────────────────────────────────
local reader = require("wechat_ocr.reader")
local ok, err = reader.init()
if not ok then io.stderr:write("reader.init 失败: " .. tostring(err) .. "\n"); os.exit(1) end
local last, e = reader.bottom()
reader.close()
if not last then io.stderr:write("读取失败: " .. tostring(e) .. "\n"); os.exit(1) end
if last == "" then io.stderr:write("第三列未读到消息\n"); os.exit(1) end
print("最后消息: " .. last)

if mode == "peek" then os.exit(0) end

-- ── 第二步：转发大脑（走 /tui，实时可见、可人工介入） ───────
local function tui_attached()
    return os.execute("pgrep -f 'opencode attach' >/dev/null 2>&1") == 0
end

if not tui_attached() then
    io.stderr:write("[once] 警告: opencode TUI 未运行，指令无法处理；请先 operator/start.sh\n")
end

local tmp = os.tmpname()
local f = io.open(tmp, "w"); f:write(cjson.encode({ text = "[微信输入] " .. last })); f:close()
os.execute(string.format(
    "sh -c 'curl -s --max-time 10 -X POST -H \"Content-Type: application/json\" --data-binary @%s \"%s/tui/append-prompt\" >/dev/null 2>&1; "
    .. "curl -s --max-time 10 -X POST -H \"Content-Type: application/json\" -d \"{}\" \"%s/tui/submit-prompt\" >/dev/null 2>&1; rm -f %s' >/dev/null 2>&1",
    tmp, AGENT_URL, AGENT_URL, tmp))
print("已转发大脑: [微信输入] " .. last)
