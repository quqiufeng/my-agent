local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;" .. package.path

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local since, lang, limit, to = "daily", "", 15, "文件传输助手"
local text_only, show, send = false, false, true

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--since" then since = arg[i + 1] or "daily"; i = i + 2
    elseif a == "--lang" then lang = arg[i + 1] or ""; i = i + 2
    elseif a == "--limit" then limit = tonumber(arg[i + 1]) or 15; i = i + 2
    elseif a == "--to" then to = arg[i + 1] or "文件传输助手"; i = i + 2
    elseif a == "--text" then text_only = true; i = i + 1
    elseif a == "--show" then show = true; i = i + 1
    elseif a == "--no-send" then send = false; i = i + 1
    else i = i + 1 end
end

print("== GitHub " .. since .. " 热门 ==")

if text_only then
    local ak = require("agentkit")
    local gh = ak.app("github")
    for _, line in ipairs(gh.brief({ since = since, lang = lang, limit = limit })) do
        print(line)
    end
    os.exit(0)
end

local stamp = os.date("%Y%m%d_%H%M%S")
local html = "/tmp/myagent_gittrend_" .. stamp .. ".html"
local png = "/tmp/myagent_gittrend_" .. stamp .. ".png"
local report = "/opt/my-agent/operator/report"

local rc = os.execute("luajit " .. q(report .. "/github_trending.lua") .. " " ..
    q(html) .. " " .. q(since) .. " " .. q(lang) .. " " .. tostring(limit))
if rc ~= 0 then io.stderr:write("生成 HTML 失败\n"); os.exit(1) end

rc = os.execute(q(report .. "/render.sh") .. " " .. q(html) .. " " .. q(png) .. " 820 >/dev/null")
if rc ~= 0 then io.stderr:write("渲染失败\n"); os.exit(1) end
print("图片: " .. png)

if show then
    os.execute("xdg-open " .. q(png) .. " >/dev/null 2>&1 &")
end

if send then
    if os.execute(q(DIR .. "/wechat_send_file.sh") .. " " .. q(png) ..
        " --to " .. q(to) .. " >/dev/null 2>&1") == 0 then
        print("已发微信 → " .. to)
    end
end
