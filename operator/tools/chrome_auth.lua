package.path = "/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;" .. package.path
local ak = require("agentkit")
local ch = ak.app("chrome")

local a = arg[1] or "enable"
local sec = tonumber(arg[2] or "30") or 30

if a == "enable" then
    local ok, m = ch.enable_remote_debugging()
    print(ok and ("已授权: " .. tostring(m)) or ("未成功: " .. tostring(m)))
    os.exit(ok and 0 or 1)
elseif a == "consent" then
    local ok, m = ch.accept_consent()
    print(ok and ("已点同意: " .. tostring(m)) or "无同意框")
elseif a == "watch" then
    local ok = ch.watch_consent(sec)
    print(ok and "已点同意" or "超时未见")
elseif a == "daemon" then
    ch.consent_daemon(2)
elseif a == "status" then
    local bar = ch.controlled_bar()
    print("端口9222: " .. tostring(ch.port_open(9222)))
    print("受控状态: " .. (bar and ("是（" .. tostring(bar) .. "）") or "否"))
else
    io.stderr:write("用法: chrome_auth.sh [enable|consent|watch <秒>|status]\n")
    os.exit(2)
end
