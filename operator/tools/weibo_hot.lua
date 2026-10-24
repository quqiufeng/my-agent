local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
require("dotenv").load()

local cjson = require("cjson")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local to, limit, display, send = "文件传输助手", 15, false, true
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--to" then
        if not arg[i + 1] then io.stderr:write("--to 缺少会话名\n"); os.exit(2) end
        to = arg[i + 1]; i = i + 2
    elseif a == "--limit" then
        limit = tonumber(arg[i + 1]) or 15; i = i + 2
    elseif a == "--display" then display = true; send = false; i = i + 1
    elseif a == "--no-send" then send = false; i = i + 1
    else i = i + 1 end
end

local cookie = os.getenv("WEIBO_COOKIE") or ""
if cookie == "" then
    local f = io.open((os.getenv("HOME") or "/root") .. "/.myagent_weibo_cookie", "r")
    if f then cookie = (f:read("*a") or ""):gsub("%s+$", ""); f:close() end
end

local ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124 Safari/537.36"
local cmd = "curl -s --max-time 20 -A " .. q(ua) ..
    " -H " .. q("Referer: https://weibo.com/") .. " "
if cookie ~= "" then cmd = cmd .. "-b " .. q(cookie) .. " " end
cmd = cmd .. q("https://weibo.com/ajax/side/hotSearch")

local p = io.popen(cmd)
local raw = p and p:read("*a") or ""
if p then p:close() end
local ok, res = pcall(cjson.decode, raw)
local realtime = ok and res and res.data and res.data.realtime or nil
if not realtime or #realtime == 0 then
    io.stderr:write("未取到热搜（cookie 失效？）\n")
    os.exit(1)
end

local stamp = os.date("%Y%m%d_%H%M%S")
local out = "/tmp/myagent_weibohot_" .. stamp
local rows = {}
for n = 1, math.min(limit, #realtime) do
    local item = realtime[n]
    local word = item.word or ""
    if word ~= "" then
        rows[#rows + 1] = string.format("%d\t%s\t%s", n, word, tostring(item.num or 0))
    end
end
if #rows == 0 then
    io.stderr:write("未取到热搜（cookie 失效？）\n")
    os.exit(1)
end

local tf = assert(io.open(out .. ".tsv", "w"))
tf:write(table.concat(rows, "\n"), "\n")
tf:close()

local report = "/opt/my-agent/operator/report"
local rc = os.execute("luajit " .. q(report .. "/weibo_hot.lua") .. " " ..
    q(out .. ".html") .. " " .. q(out .. ".txt") .. " " .. q(out .. ".tsv"))
if rc ~= 0 then io.stderr:write("生成排版失败\n"); os.exit(1) end

local txt = io.open(out .. ".txt", "r")
local body = txt and txt:read("*a") or ""
if txt then txt:close() end

if display then io.write(body); os.exit(0) end
io.write(body)

os.execute(q(report .. "/render.sh") .. " " .. q(out .. ".html") .. " " .. q(out .. ".png") .. " 820 >/dev/null 2>&1")
print("图片: " .. out .. ".png")

if send then
    local img = io.open(out .. ".png", "rb")
    if img then
        img:close()
        if os.execute(q(DIR .. "/wechat_send_file.sh") .. " " .. q(out .. ".png") ..
            " --to " .. q(to) .. " >/dev/null 2>&1") == 0 then
            print("已发图 → " .. to)
            os.execute("sleep 3")
        end
    end
    local text = io.open(out .. ".txt", "r")
    local content = text and text:read("*a") or ""
    if text then text:close() end
    if os.execute(q(DIR .. "/wechat_send.sh") .. " --to " .. q(to) .. " " .. q(content) ..
        " >/dev/null 2>&1") == 0 then
        print("已发文字 → " .. to)
    end
end
