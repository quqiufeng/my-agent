-- wechat-ocr/bridge.lua — 微信入口（常驻）
-- 轮询微信第三列「最下面一条消息」，文本变化才以 [微信输入] 转发大脑。
-- 读取用 reader（capture_all，不依赖时间戳）；用发送日志避免对大脑自己的回复产生自循环。
--
-- 用法: ./bridge.sh

package.path = "/opt/my-agent/wechat-ocr/lua/?.lua;/opt/my-agent/wechat-ocr/lua/?/init.lua;"
    .. "/opt/my-agent/wechat-ocr/?.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
    .. (package.path or "")
package.cpath = "/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;" .. (package.cpath or "")

local cjson = require("cjson")
local reader = require("wechat_ocr.reader")

local AGENT_URL = os.getenv("AGENT_URL") or "http://localhost:4097"
local OPERATOR_DIR = os.getenv("OPERATOR_DIR") or "/opt/my-agent/operator"
local SENT_LOG = os.getenv("WECHAT_SENT_LOG") or "/tmp/friday_wechat_sent.log"
local INTERVAL = tonumber(os.getenv("WECHAT_INTERVAL") or "3")

local SESSION_ID = nil

local function http_post_json(url, obj, timeout)
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

local function ensure_session()
    if SESSION_ID then return SESSION_ID end
    local body = http_post_json(AGENT_URL .. "/session?directory=" .. OPERATOR_DIR, {})
    SESSION_ID = body:match('"id":"(ses_[^"]+)"')
    if not SESSION_ID then
        io.stderr:write("[bridge] 创建大脑会话失败（opencode 未启动？）\n")
    end
    return SESSION_ID
end

-- 后台转发，不等模型跑完
local function forward(text)
    local sid = ensure_session()
    if not sid then return end
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write(cjson.encode({ parts = { { type = "text", text = "[微信输入] " .. text } } }))
    f:close()
    os.execute(string.format(
        "sh -c 'curl -s --max-time 300 -X POST -H \"Content-Type: application/json\" --data-binary @%s \"%s/session/%s/message\" >/dev/null 2>&1; rm -f %s' >/dev/null 2>&1 &",
        tmp, AGENT_URL, sid, tmp))
end

-- 大脑回程发出去的消息（含本机自己发的）记在日志里，避免被当成新消息再次处理
local function normalize(s)
    return (s:gsub("%s", ""):gsub("[%p%c]", ""))
end

local function load_sent()
    local set = {}
    local f = io.open(SENT_LOG, "r")
    if f then
        for line in f:lines() do
            if line ~= "" then set[line] = true end
        end
        f:close()
    end
    return set
end

local function is_self(text)
    local n = normalize(text)
    if n == "" then return false end
    for s in pairs(load_sent()) do
        local ns = normalize(s)
        if ns ~= "" and (ns == n or n:find(ns, 1, true) or ns:find(n, 1, true)) then
            return true
        end
    end
    return false
end

local ok, err = reader.init()
if not ok then io.stderr:write("[bridge] reader.init 失败: " .. tostring(err) .. "\n"); os.exit(1) end
io.write("[bridge] 微信入口(轮询) 启动，目标 " .. AGENT_URL .. " (dir=" .. OPERATOR_DIR .. ")\n")
io.flush()

local prev = nil
while true do
    local text, e = reader.bottom()
    if not text then
        if e then io.stderr:write("[bridge] " .. tostring(e) .. "\n") end
    elseif text ~= "" and text ~= prev then
        if prev == nil then
            io.write("[bridge] 初始消息: " .. text .. "\n")
        elseif is_self(text) then
            io.write("[bridge] 跳过(自己发的): " .. text .. "\n")
        else
            io.write("[微信输入] " .. text .. "\n")
            io.flush()
            forward(text)
        end
        prev = text
    end
    os.execute("sleep " .. INTERVAL)
end
reader.close()
