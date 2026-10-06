-- wechat-ocr/bridge.lua — 微信入口（常驻守护，用户白名单模式）
-- 白名单: whitelist.txt（每行一个会话名），第一个是「文件传输助手」。
-- 每 POLL 秒后台轮询（不聚焦、不点开会话）：
--   抓微信窗口(import -window，遮挡可读) → OCR 第二列 → 对白名单里每个会话
--   找到其行 且 该行有未读红点（双重认证）→ 读该行预览(=最新消息)
--   → 消息必须以标签开头（ai / ai助手，`#` 可省）才当作指令，去掉标签后以
--     [微信输入:<会话名>] 转发大脑。红点保留，不自动已读；不带标签的不响应。
-- 大脑回复经 operator/tools/wechat_send.sh --to <会话名> 发送，自动加 ai助手 前缀。
-- 用法: ./bridge.sh

package.path = "/opt/my-agent/wechat-ocr/?.lua;/opt/my-agent/wechat-ocr/lua/?.lua;"
    .. "/opt/my-agent/wechat-ocr/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
    .. (package.path or "")
package.cpath = "/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;" .. (package.cpath or "")

local cjson = require("cjson")
local watcher = require("wechat_ocr.watcher")

local DIR       = os.getenv("WECHAT_DIR") or "/opt/my-agent/wechat-ocr"
local AGENT_URL = os.getenv("AGENT_URL") or "http://localhost:4097"
local SENT_LOG  = os.getenv("WECHAT_SENT_LOG") or "/tmp/myagent_wechat_sent.log"
local POLL      = tonumber(os.getenv("WECHAT_POLL_SEC") or "10")   -- 轮询间隔（秒）
local ONCE      = os.getenv("WECHAT_ONCE") == "1"                  -- 只跑一轮（调试）
local DRY       = os.getenv("WECHAT_DRY") == "1"                   -- 只打印不转发（调试）
local FORCE     = os.getenv("WECHAT_FORCE_UNREAD") == "1"          -- 无视红点强制读取（调试）
local REPLY_WAIT = tonumber(os.getenv("WECHAT_REPLY_WAIT") or "40") -- 等大脑回复上限（秒）
local WHITELIST = os.getenv("WECHAT_WHITELIST") or (DIR .. "/whitelist.txt")
local CMD_TAG   = os.getenv("WECHAT_CMD_TAG") or "ai助手"           -- 指令标签（# 可选）

-- 取指令正文：白名单消息以标签开头（`ai`/`ai助手`，`#` 可省；手机不好打#）。
-- 容错：`#` 可能被 OCR 成「并/井」，`ai` 的 i 可能变 1/l/L。命中返回正文，否则 nil。
local function to_command(text)
    local t = text:gsub("^%s+", ""):gsub("^[#并井]%s*", "")
    local rest, n = t:gsub("^[Aa][Ii1lL]", "", 1)
    if n == 0 then return nil end
    if rest:match("^[A-Za-z0-9]") then return nil end   -- 排除 air/aid 等英文词
    rest = rest:gsub("^%s*助手", ""):gsub("^%s+", "")
    return (rest:gsub("%s+$", ""))
end

-- ── 白名单 ──────────────────────────────────────────────────
local function load_users()
    local users = {}
    local f = io.open(WHITELIST, "r")
    if f then
        for line in f:lines() do
            line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then users[#users + 1] = line end
        end
        f:close()
    end
    if #users == 0 then users = { "文件传输助手" } end
    return users
end

-- ── 转发大脑（/tui，实时可见、可人工介入），带来源会话名 ─────
local function tui_attached()
    return os.execute("pgrep -f 'opencode[ ]attach' >/dev/null 2>&1") == 0
end

local function forward(user, text)
    if not tui_attached() then
        io.stderr:write("[bridge] opencode TUI 未运行，自动拉起...\n")
        os.execute("/opt/my-agent/operator/ensure_tui.sh >/dev/null 2>&1")
    end
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write(cjson.encode({ text = "[微信输入:" .. user .. "] " .. text }))
    f:close()
    os.execute(string.format(
        "sh -c 'curl -s --max-time 10 -X POST -H \"Content-Type: application/json\" --data-binary @%s \"%s/tui/append-prompt\" >/dev/null 2>&1; "
        .. "curl -s --max-time 10 -X POST -H \"Content-Type: application/json\" -d \"{}\" \"%s/tui/submit-prompt\" >/dev/null 2>&1; rm -f %s' >/dev/null 2>&1",
        tmp, AGENT_URL, AGENT_URL, tmp))
end

-- ── USB 音响提示音 ──────────────────────────────────────────
local NOTIFY_WAV = os.getenv("WECHAT_NOTIFY_WAV") or "/tmp/myagent_notify.wav"

local function notify()
    local f = io.open(NOTIFY_WAV, "rb")
    if f then f:close() else
        os.execute(string.format(
            "ffmpeg -y -f lavfi -i \"sine=frequency=880:duration=0.25\" "
            .. "-af volume=0.5 '%s' >/dev/null 2>&1", NOTIFY_WAV))
    end
    local sink = os.getenv("VOICE_SINK") or ""
    if sink ~= "" then
        os.execute(string.format("pw-play --target '%s' '%s' >/dev/null 2>&1 &", sink, NOTIFY_WAV))
    else
        os.execute(string.format("pw-play '%s' >/dev/null 2>&1 &", NOTIFY_WAV))
    end
end

-- ── 防自循环：大脑回程发出去的消息记在日志里 ────────────────
local function normalize(s)
    return (s:gsub("%s", ""):gsub("[%p%c]", ""))
end

local function is_self(text)
    local n = normalize(text)
    if n == "" then return false end
    local f = io.open(SENT_LOG, "r")
    if not f then return false end
    local hit = false
    for line in f:lines() do
        if normalize(line) == n then hit = true; break end
    end
    f:close()
    return hit
end

local function sent_lines()
    local n = 0
    local f = io.open(SENT_LOG, "r")
    if f then for _ in f:lines() do n = n + 1 end; f:close() end
    return n
end

-- ── 每个会话的上次转发（去重，持久化） ──────────────────────
local LAST_FILE = os.getenv("WECHAT_LAST_FILE") or "/tmp/myagent_wechat_last"
local last = {}
local function load_last()
    local f = io.open(LAST_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local u, t = line:match("^([^\t]+)\t(.*)$")
        if u and t and t ~= "" then last[u] = t end
    end
    f:close()
end
local function save_last()
    local f = io.open(LAST_FILE, "w")
    if f then
        for u, t in pairs(last) do f:write(u .. "\t" .. t .. "\n") end
        f:close()
    end
end

-- ── 启动 ────────────────────────────────────────────────────
local ok, err = watcher.init()
if not ok then io.stderr:write("[bridge] watcher.init 失败: " .. tostring(err) .. "\n"); os.exit(1) end

local USERS = load_users()
load_last()
io.write(string.format("[bridge] 微信白名单监控启动：每 %d 秒轮询，用户[%s]，目标 %s\n",
    POLL, table.concat(USERS, ","), AGENT_URL))
io.flush()

-- 全程后台读第二列：不聚焦、不点开会话，红点保留。
while true do
    local shot, win = watcher.window_capture()
    local res, badges = nil, {}
    if shot then
        res = watcher.ocr(shot, win)
        badges = watcher.red_badges(shot, win)
    end
    local any_unread = false

    for _, user in ipairs(USERS) do
        local row = res and watcher.find_row(res, user)
        if row then
            local unread = FORCE or watcher.row_has_badge(row, badges)
            if not unread then
                last[user] = nil                 -- 红点已清，允许同样消息再次处理
            else
                any_unread = true
                io.write("[bridge] 「" .. user .. "」有未读\n")
                notify()                          -- USB 音响提示音
                local text, perr = watcher.read_preview(shot, win, row)
                local cmd = text and to_command(text) or nil
                if text and text ~= "" and text ~= last[user] then
                    if not cmd then
                        io.write("[bridge] 跳过(无 " .. CMD_TAG .. " 标签): " .. text .. "\n")
                    elseif cmd == "" then
                        io.write("[bridge] 跳过(空指令)\n")
                    elseif is_self(text) then
                        io.write("[bridge] 跳过(自己发的): " .. text .. "\n")
                    elseif DRY then
                        io.write("[bridge][DRY] 将转发 -> " .. user .. ": " .. cmd .. "\n")
                        last[user] = text; save_last()
                    else
                        io.write("[微信输入:" .. user .. "] " .. cmd .. "\n")
                        io.flush()
                        local before = sent_lines()
                        forward(user, cmd)
                        last[user] = text; save_last()
                        -- 等大脑回程（回微信会写发送日志）
                        for _ = 1, REPLY_WAIT do
                            if sent_lines() > before then break end
                            os.execute("sleep 1")
                        end
                        os.execute("sleep 4")
                    end
                else
                    io.write("[bridge] 未读到新消息 (" .. tostring(perr or "重复") .. ")\n")
                end
            end
        end
    end

    if not any_unread then io.write("[bridge] 白名单内无未读\n") end
    io.flush()
    if ONCE then break end
    os.execute("sleep " .. POLL)
end

watcher.close()
