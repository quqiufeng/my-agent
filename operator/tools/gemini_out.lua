local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path

local cjson = require("cjson")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local target = arg[1] or ""
local parts = {}
for i = 2, #arg do parts[#parts + 1] = arg[i] end
local text = table.concat(parts, " ")

if text == "" and os.execute("test -t 0") ~= 0 then
    text = io.read("*a") or ""
end

if target == "" or text == "" then
    io.stderr:write("用法: gemini_out.sh <wechat|opencode> \"文本\"   （文本也可从 stdin 读）\n")
    os.exit(2)
end

target = target:lower()
if target == "wechat" or target == "wx" or target == "weixin" then
    os.execute(q(DIR .. "/wechat_send.sh") .. " " .. q(text))
    os.exit(0)
elseif target == "opencode" or target == "oc" or target == "tui" then
    local url = os.getenv("AGENT_URL") or "http://localhost:4097"
    local payload = cjson.encode({ text = "[Gemini] " .. text })
    local cmd = "curl -sf -X POST -H 'Content-Type: application/json' --data " ..
        q(payload) .. " " .. q(url .. "/tui/append-prompt") .. " >/dev/null"
    if os.execute(cmd) ~= 0 then
        io.stderr:write("转发 opencode 失败（TUI 未运行？）\n")
        os.exit(1)
    end
    if os.execute("curl -sf -X POST -H 'Content-Type: application/json' -d '{}' " ..
        q(url .. "/tui/submit-prompt") .. " >/dev/null") ~= 0 then
        io.stderr:write("submit 失败\n")
        os.exit(1)
    end
    print("已发送到 opencode(/tui)")
else
    io.stderr:write("未知目标: " .. target .. "（可用 wechat | opencode）\n")
    os.exit(2)
end
