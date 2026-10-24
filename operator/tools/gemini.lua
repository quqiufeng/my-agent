local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local bg = require("bgjob")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function size(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local n = f:seek("end") or 0
    f:close()
    return n
end

local question, to, img, send, display = nil, "文件传输助手", true, true, false
local fg = false
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--display" then display = true; img = false; send = false; i = i + 1
    elseif a == "--to" then to = arg[i + 1] or "文件传输助手"; i = i + 2
    elseif a == "--no-image" then img = false; i = i + 1
    elseif a == "--no-send" then send = false; i = i + 1
    elseif a == "--fg" then fg = true; i = i + 1
    else
        if not question then question = a end
        i = i + 1
    end
end

if not question or question == "" then
    io.stderr:write("用法: gemini.sh <问题> [--display] [--to 会话]\n")
    os.exit(2)
end

if not display and not fg and os.getenv("BG_WORKER") ~= "1" then
    local j = bg.spawn_self(arg, "gemini")
    print("已后台问 Gemini job=" .. j.id)
    print("查看进度: tools/jobs.sh tail " .. j.id)
    os.exit(0)
end

if os.execute("ss -ltn 2>/dev/null | grep -q ':9222 '") ~= 0 then
    os.execute(q(DIR .. "/chrome_debug.sh") .. " >/dev/null 2>&1")
    os.execute("sleep 2")
end

local stamp = os.date("%Y%m%d_%H%M%S")
local out = "/tmp/myagent_gemini_" .. stamp
for attempt = 1, 3 do
    os.execute("timeout 120 node /opt/my-agent/agentkit/tools/gemini.js " ..
        q(question) .. " > " .. q(out .. ".ans") .. " 2>/dev/null")
    if size(out .. ".ans") > 0 then break end
    io.stderr:write("第" .. attempt .. "次未取到，重试...\n")
    os.execute("sleep 2")
end

local f = io.open(out .. ".ans", "r")
local answer = f and (f:read("*a") or "") or ""
if f then f:close() end
if answer == "" then io.stderr:write("未取到 Google AI 回答\n"); os.exit(1) end

if display then
    io.write(answer)
    if answer:sub(-1) ~= "\n" then io.write("\n") end
    os.exit(0)
end
io.write(answer)
if answer:sub(-1) ~= "\n" then io.write("\n") end

local report = "/opt/my-agent/operator/report"
os.execute("luajit " .. q(report .. "/gemini_report.lua") .. " " ..
    q(out .. ".html") .. " " .. q(out .. ".txt") .. " " .. q(question) .. " " ..
    q(out .. ".ans") .. " 2>/dev/null")

if img then
    os.execute(q(report .. "/render.sh") .. " " .. q(out .. ".html") .. " " ..
        q(out .. ".png") .. " 820 >/dev/null 2>&1")
    print("图片: " .. out .. ".png")
end

if send then
    if img and size(out .. ".png") > 0 then
        if os.execute(q(DIR .. "/wechat_send_file.sh") .. " " .. q(out .. ".png") ..
            " --to " .. q(to) .. " >/dev/null 2>&1") == 0 then
            print("已发图 → " .. to)
            os.execute("sleep 3")
        end
    end
    local tf = io.open(out .. ".txt", "r")
    local body = tf and (tf:read("*a") or "") or ""
    if tf then tf:close() end
    if os.execute(q(DIR .. "/wechat_send.sh") .. " --to " .. q(to) .. " " .. q(body) ..
        " >/dev/null 2>&1") == 0 then
        print("已发文字 → " .. to)
    end
end
