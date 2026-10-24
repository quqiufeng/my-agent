local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
require("dotenv").load()
local page = require("page_capture")
local cjson = require("cjson")

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
            io.stderr:write("用法: quote_web.sh [名称或代码] [--to 会话]\n")
            os.exit(2)
        end
        to = arg[i + 1]; i = i + 2
    else
        if not kw then kw = arg[i] end
        i = i + 1
    end
end

local sohu = "https://q.stock.sohu.com/zs/000001/index.shtml"

if kw and kw ~= "" then
    local key = os.getenv("FUYAO_API_KEY")
    if key and key ~= "" then
        local api = "https://fuyao.aicubes.cn/api/meta/tickers/search?q=" ..
            urlencode(kw) .. "&limit=10"
        local p = io.popen("curl -s --max-time 12 -H " ..
            q("X-api-key: " .. key) .. " " .. q(api) .. " 2>/dev/null")
        local raw = p and p:read("*a") or ""
        if p then p:close() end
        local ok, res = pcall(cjson.decode, raw)
        local items = ok and res and res.data and res.data.item or nil
        local pick
        if items then
            for _, it in ipairs(items) do
                if it.asset_type == "a-share" or it.asset_type == "a-share-index" then
                    pick = it
                    break
                end
            end
            if not pick then pick = items[1] end
        end
        if pick and pick.ticker and pick.ticker ~= "" then
            if pick.asset_type == "a-share-index" then
                sohu = "https://q.stock.sohu.com/zs/" .. pick.ticker .. "/index.shtml"
            else
                sohu = "https://q.stock.sohu.com/cn/" .. pick.ticker .. "/index.shtml"
            end
        end
    end
end

print("打开: " .. sohu)
if os.getenv("PAGE_SHOT_URL_ONLY") == "1" then os.exit(0) end

page.open(sohu)
local out = page.capture("/tmp/myagent_quote")
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
