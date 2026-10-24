local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
require("dotenv").load()

local cjson = require("cjson")
local BASE = "https://fuyao.aicubes.cn"
local KEY = os.getenv("FUYAO_API_KEY") or ""
if KEY == "" then io.stderr:write("缺少 FUYAO_API_KEY\n"); os.exit(3) end

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function urlencode(s)
    return (s:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function api(path)
    local p = io.popen("curl -s --max-time 12 -H " ..
        q("X-api-key: " .. KEY) .. " " .. q(BASE .. path) .. " 2>/dev/null")
    local raw = p and p:read("*a") or ""
    if p then p:close() end
    local ok, res = pcall(cjson.decode, raw)
    return ok and res or nil
end

local function resolve(kw)
    local res = api("/api/meta/tickers/search?q=" .. urlencode(kw) .. "&limit=10")
    local items = res and res.data and res.data.item or nil
    if not items then return nil end
    local pick
    for _, it in ipairs(items) do
        if it.asset_type == "a-share" or it.asset_type == "a-share-index" then
            pick = it; break
        end
    end
    if not pick then pick = items[1] end
    if not pick then return nil end
    return pick.thscode, pick.name, pick.asset_type
end

local function snapshot(thscode, asset)
    local ep = (asset == "a-share-index") and "/api/a-share-index/prices/snapshot"
        or "/api/a-share/prices/snapshot"
    local res = api(ep .. "?thscodes=" .. urlencode(thscode))
    if not res or (res.code ~= 0 and res.code ~= "0") then
        ep = (ep:find("a-share-index", 1, true)) and "/api/a-share/prices/snapshot"
            or "/api/a-share-index/prices/snapshot"
        res = api(ep .. "?thscodes=" .. urlencode(thscode))
    end
    local it = res and res.data and res.data.item and res.data.item[1]
    if not it then return nil end
    return it
end

local to, show, send = "", false, true
local i = 1
while i <= #arg do
    if arg[i] == "--to" then to = arg[i + 1] or ""; i = i + 2
    elseif arg[i] == "--show" then show = true; i = i + 1
    elseif arg[i] == "--no-send" then send = false; i = i + 1
    else i = i + 1 end
end

local data = "/tmp/myagent_dash.tsv"
local tsv = assert(io.open(data, "w"))

local index_names = os.getenv("DASH_INDICES") or "上证指数 深证成指 创业板指 沪深300"
for nm in index_names:gmatch("%S+") do
    local code, name, asset = resolve(nm)
    if code then
        local it = snapshot(code, asset)
        if it then
            tsv:write(table.concat({ "IDX", name, tostring(it.last_price),
                tostring(it.price_change), tostring(it.price_change_ratio_pct),
                tostring(it.open_price), tostring(it.high_price), tostring(it.low_price) }, "\t"), "\n")
        end
    end
end

local kdays = tonumber(os.getenv("DASH_KDAYS")) or 40
local now = os.time()
local kpath = "/api/a-share-index/prices/historical?thscode=000001.SH&interval=1d&start=" ..
    tostring((now - kdays * 86400) * 1000) .. "&end=" .. tostring(now * 1000) .. "&adjust=forward"
local kres = api(kpath)
if not kres or (kres.code ~= 0 and kres.code ~= "0") then
    kpath = "/api/a-share/prices/historical?thscode=000001.SH&interval=1d&start=" ..
        tostring((now - kdays * 86400) * 1000) .. "&end=" .. tostring(now * 1000) .. "&adjust=forward"
    kres = api(kpath)
end
if kres and kres.data and kres.data.item then
    local closes = {}
    for _, it in ipairs(kres.data.item) do
        if it.close_price then closes[#closes + 1] = tostring(it.close_price) end
    end
    if #closes > 0 then
        tsv:write("K\t上证指数\t" .. table.concat(closes, ",") .. "\n")
    end
end

local wlpath = os.getenv("STOCK_LIST") or ((os.getenv("HOME") or "/root") .. "/.myagent_stocks.txt")
local wf = io.open(wlpath, "r")
if not wf then
    wf = io.open(wlpath, "w")
    if wf then
        wf:write("贵州茅台\n宁德时代\n比亚迪\n招商银行\n中国平安\n")
        wf:close()
    end
    wf = io.open(wlpath, "r")
end
if wf then
    for line in wf:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local code, name, asset = resolve(line)
            if code then
                local it = snapshot(code, asset)
                if it then
                    tsv:write(table.concat({ "WL", name, tostring(it.last_price),
                        tostring(it.price_change), tostring(it.price_change_ratio_pct) }, "\t"), "\n")
                end
            end
        end
    end
    wf:close()
end
tsv:close()

local check = io.open(data, "r")
local size = check and check:seek("end") or 0
if check then check:close() end
if not size or size == 0 then io.stderr:write("没有数据（检查自选股/网络）\n"); os.exit(1) end

local out = "/tmp/myagent_dash_" .. os.date("%Y%m%d_%H%M%S") .. ".png"
local html = "/tmp/myagent_dash_" .. tostring(os.time()) .. ".html"
if os.execute("luajit " .. q(DIR .. "/dash_html.lua") .. " " .. q(data) .. " " ..
    q(html) .. " " .. q("行情大屏") .. " >/dev/null") ~= 0 then
    io.stderr:write("生成大屏 HTML 失败\n")
    os.exit(1)
end

local chrome
local p = io.popen("command -v google-chrome || command -v google-chrome-stable || command -v chromium || command -v chromium-browser")
if p then chrome = p:read("*l"); p:close() end
if not chrome or chrome == "" then io.stderr:write("需要 Chrome/Chromium（无头截图）\n"); os.exit(3) end

local w = os.getenv("DASH_W") or "820"
local h = os.getenv("DASH_H") or "1380"
local cmd = q(chrome) .. " --headless=new --disable-gpu --no-sandbox --hide-scrollbars" ..
    " --window-size=" .. w .. "," .. h .. " --virtual-time-budget=4000" ..
    " --screenshot=" .. q(out) .. " " .. q("file://" .. html) .. " >/dev/null 2>&1"
os.execute(cmd)
os.remove(html)

local f = io.open(out, "rb")
if not f then io.stderr:write("大屏渲染失败\n"); os.exit(1) end
local sz = f:seek("end"); f:close()
if not sz or sz == 0 then io.stderr:write("大屏渲染失败\n"); os.exit(1) end
print("大屏已生成: " .. out)

if show then os.execute("display -window root " .. q(out) .. " >/dev/null 2>&1 &") end
if send then
    local sendcmd = q(DIR .. "/wechat_send_file.sh") .. " " .. q(out)
    if to ~= "" then sendcmd = sendcmd .. " --to " .. q(to) end
    if os.execute(sendcmd) ~= 0 then
        io.stderr:write("发送微信失败\n")
        os.exit(1)
    end
    print(to ~= "" and ("已发到微信「" .. to .. "」") or "已发到微信文件传输助手")
end
