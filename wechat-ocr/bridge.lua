-- wechat-ocr/bridge.lua — 微信入口桥
-- 监控微信聊天 → 新消息以 [微信输入] 前缀转发给大脑(opencode 4097)
--
-- 用法: ./bridge.sh        （自动设置 LD_LIBRARY_PATH / LUA_PATH）

package.path = "/opt/my-agent/wechat-ocr/lua/?.lua;/opt/my-agent/wechat-ocr/lua/?/init.lua;"
    .. "/opt/my-agent/wechat-ocr/?.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
    .. (package.path or "")
package.cpath = "/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;" .. (package.cpath or "")

local cjson = require("cjson")
local robot = require("wechat_robot")

local AGENT_URL = os.getenv("AGENT_URL") or "http://localhost:4097"

-- 用临时文件 + curl 转发，避免命令行转义问题
local function http_post(url, obj)
    local body = cjson.encode(obj)
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    if not f then return false end
    f:write(body)
    f:close()
    local cmd = string.format(
        "curl -sf -X POST -H 'Content-Type: application/json' --data-binary @%s %s >/dev/null 2>&1",
        tmp, url)
    local ok = os.execute(cmd)
    os.remove(tmp)
    return ok == true or ok == 0
end

local function to_brain(text)
    http_post(AGENT_URL .. "/tui/append-prompt", { text = "[微信输入] " .. text })
    http_post(AGENT_URL .. "/tui/submit-prompt", {})
end

local ok, err = robot.init()
if not ok then
    io.stderr:write("[bridge] wechat init 失败: " .. tostring(err) .. "\n")
    os.exit(1)
end
io.write("[bridge] 微信入口已启动，转发目标 " .. AGENT_URL .. "\n")
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
