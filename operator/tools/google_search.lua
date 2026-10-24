local DIR = (arg[0] or ""):match("^(.*)/") or "."

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local kw, news, to, img, send = nil, false, "文件传输助手", true, true
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--news" then news = true; i = i + 1
    elseif a == "--to" then to = arg[i + 1] or "文件传输助手"; i = i + 2
    elseif a == "--no-image" then img = false; i = i + 1
    elseif a == "--no-send" then send = false; i = i + 1
    else
        if not kw then kw = a end
        i = i + 1
    end
end

if not kw or kw == "" then
    io.stderr:write("用法: google_search.sh <关键词> [--news] [--to 会话]\n")
    os.exit(2)
end

if not os.getenv("DISPLAY") then
    -- 尽量使用图形会话；CDP 本身不依赖，仅用于 Chrome 启动
    local p = io.popen("pgrep -x pcmanfm-qt | head -1")
    local pid = p and p:read("*l") or nil
    if p then p:close() end
    if pid and pid ~= "" then
        os.execute("DISPLAY=:0")
    end
end

if os.execute("ss -ltn 2>/dev/null | grep -q ':9222 '") ~= 0 then
    os.execute(q(DIR .. "/chrome_debug.sh") .. " >/dev/null 2>&1")
    os.execute("sleep 2")
end

local stamp = os.date("%Y%m%d_%H%M%S")
local out = "/tmp/myagent_google_" .. stamp
local mode = news and "news" or "search"
local report = "/opt/my-agent/operator/report"

os.execute("luajit " .. q(report .. "/google_report.lua") .. " " ..
    q(out .. ".html") .. " " .. q(out .. ".txt") .. " " .. q(kw) .. " " .. q(mode) ..
    " 2>/dev/null")

local tf = io.open(out .. ".txt", "r")
if not tf then io.stderr:write("未取到结果\n"); os.exit(1) end
local body = tf:read("*a") or ""
tf:close()
if body == "" then io.stderr:write("未取到结果\n"); os.exit(1) end

if img then
    os.execute(q(report .. "/render.sh") .. " " .. q(out .. ".html") .. " " ..
        q(out .. ".png") .. " 820 >/dev/null 2>&1")
    local pf = io.open(out .. ".png", "rb")
    if pf then pf:close() end
    print("图片: " .. out .. ".png")
end
io.write(body)

if send then
    local im = io.open(out .. ".png", "rb")
    if img and im then
        im:close()
        if os.execute(q(DIR .. "/wechat_send_file.sh") .. " " .. q(out .. ".png") ..
            " --to " .. q(to) .. " >/dev/null 2>&1") == 0 then
            print("已发图 → " .. to)
            os.execute("sleep 1")
        end
    elseif im then
        im:close()
    end
    if os.execute(q(DIR .. "/wechat_send.sh") .. " --to " .. q(to) .. " " .. q(body) ..
        " >/dev/null 2>&1") == 0 then
        print("已发文字 → " .. to)
    end
end
