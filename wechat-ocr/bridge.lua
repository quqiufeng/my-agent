-- wechat-ocr/bridge.lua — 微信入口桥
-- 监控微信聊天 → 新消息以 [微信输入] 前缀转发给大脑(opencode 4097)
--
-- 用法: ./bridge.sh        （自动设置 LD_LIBRARY_PATH / LUA_PATH）
-- 转发使用 opencode 的 session API（/tui/* 在无 TUI 时不触发）：
--   启动时 POST /session?directory=<operator> 建会话，再 POST /session/{id}/message

package.path = "/opt/my-agent/wechat-ocr/lua/?.lua;/opt/my-agent/wechat-ocr/lua/?/init.lua;"
    .. "/opt/my-agent/wechat-ocr/?.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
    .. (package.path or "")
package.cpath = "/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;" .. (package.cpath or "")

local cjson = require("cjson")
local robot = require("wechat_robot")

local AGENT_URL = os.getenv("AGENT_URL") or "http://localhost:4097"
local OPERATOR_DIR = os.getenv("OPERATOR_DIR") or "/opt/my-agent/operator"
local SESSION_ID = nil

-- POST JSON（obj 为 Lua table），返回响应体
local function http_post_json(url, obj)
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    if not f then return "" end
    f:write(cjson.encode(obj))
    f:close()
    local out = os.tmpname()
    os.execute(string.format(
        "curl -sf -X POST -H 'Content-Type: application/json' --data-binary @%s '%s' > %s 2>/dev/null",
        tmp, url, out))
    os.remove(tmp)
    local of = io.open(out, "r")
    local body = of and of:read("*a") or ""
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

local function to_brain(text)
    local sid = ensure_session()
    if not sid then return end
    local resp = http_post_json(AGENT_URL .. "/session/" .. sid .. "/message",
        { parts = { { type = "text", text = "[微信输入] " .. text } } })
    if resp == "" then io.stderr:write("[bridge] 转发失败\n") end
end

local ok, err = robot.init()
if not ok then
    io.stderr:write("[bridge] wechat init 失败: " .. tostring(err) .. "\n")
    os.exit(1)
end
io.write("[bridge] 微信入口已启动，转发目标 " .. AGENT_URL .. " (dir=" .. OPERATOR_DIR .. ")\n")
io.flush()

robot.monitor({
    interval_ms = 3000,
    on_message = function(text)
        if text and text ~= "" then
            io.write("[微信输入] " .. text .. "\n")
            io.flush()
            to_brain(text)
        end
    end,
    on_error = function(e)
        io.stderr:write("[bridge] " .. tostring(e) .. "\n")
    end,
})
robot.destroy()
