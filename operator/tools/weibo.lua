local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local page = require("page_capture")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function urlencode(s)
    return (s:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local to, kw = "", nil
local i = 1
while i <= #arg do
    if arg[i] == "--to" then
        if not arg[i + 1] then
            io.stderr:write("用法: weibo.sh <关键词> [--to 会话]\n")
            os.exit(2)
        end
        to = arg[i + 1]; i = i + 2
    else
        if not kw then kw = arg[i] end
        i = i + 1
    end
end

if not kw or kw == "" then
    io.stderr:write("用法: weibo.sh <关键词> [--to 会话]\n")
    os.exit(2)
end

local url = "https://s.weibo.com/weibo?q=" .. urlencode(kw)
print("打开: " .. url)
if os.getenv("PAGE_SHOT_URL_ONLY") == "1" then os.exit(0) end

page.open(url)
local out = page.capture("/tmp/myagent_weibo")
if not out then
    io.stderr:write("截图失败\n")
    os.exit(1)
end
print("截图: " .. out)

if os.getenv("PAGE_SHOT_DRY") == "1" then os.exit(0) end

if page.send(out, to) then
    print(to ~= "" and ("已发到微信「" .. to .. "」") or "已发到微信文件传输助手")
else
    io.stderr:write("发送微信失败\n")
    os.exit(1)
end
