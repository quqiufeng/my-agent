local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
require("dotenv").load()

local cjson = require("cjson")
local BASE = "https://fuyao.aicubes.cn"
local KEY = os.getenv("FUYAO_API_KEY") or ""
if KEY == "" then
    io.stderr:write("缺少 FUYAO_API_KEY（请在 ~/.env 配置，见 fuyao.aicubes.cn 的 API Key 管理）\n")
    os.exit(3)
end

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
    return ok and res or nil, raw
end

local function resolve(kw)
    local res = api("/api/meta/tickers/search?q=" .. urlencode(kw) .. "&limit=10")
    local items = res and res.data and res.data.item or nil
    if not items then return nil end
    local pick
    for _, it in ipairs(items) do
        if it.asset_type == "a-share" then pick = it; break end
    end
    if not pick then pick = items[1] end
    if not pick then return nil end
    return pick.thscode, pick.name, pick.asset_type
end

local function quote(thscode, name, asset)
    local ep = (asset == "a-share-index") and "/api/a-share-index/prices/snapshot"
        or "/api/a-share/prices/snapshot"
    local res = api(ep .. "?thscodes=" .. urlencode(thscode))
    if not res or (res.code ~= 0 and res.code ~= "0") then
        ep = (ep:find("a-share-index", 1, true)) and "/api/a-share/prices/snapshot"
            or "/api/a-share-index/prices/snapshot"
        res = api(ep .. "?thscodes=" .. urlencode(thscode))
    end
    if not res or (res.code ~= 0 and res.code ~= "0") then
        local msg = res and res.message or "?"
        print(thscode .. ": 取行情失败（" .. tostring(msg) .. "）")
        return false
    end
    local it = res.data and res.data.item and res.data.item[1]
    if not it then print(thscode .. ": 取行情失败（空数据）"); return false end

    local ch = tonumber(it.price_change) or 0
    local arrow = ch > 0 and "▲" or (ch < 0 and "▼" or "")
    local ratio = tonumber(it.price_change_ratio_pct) or 0
    local pct = math.floor(ratio * 100 + 0.5) / 100

    local line = string.format(
        "%s(%s)  现价 %s  %s%s (%s%%)  开%s 高%s 低%s 昨收%s",
        name, thscode, tostring(it.last_price), arrow, tostring(it.price_change),
        tostring(pct), tostring(it.open_price), tostring(it.high_price),
        tostring(it.low_price), tostring(it.prev_price))

    local ts_ms = tonumber(res.data.timestamp)
    local ts = ts_ms and os.date("%Y-%m-%d %H:%M", math.floor(ts_ms / 1000)) or "未知"
    print(line .. "  [" .. ts .. "]")
    return true
end

local cmd = arg[1] or ""
if cmd == "" or cmd == "-h" or cmd == "--help" or cmd == "help" then
    print("用法: stock.sh <名称或代码>   |   stock.sh list")
elseif cmd == "list" then
    local path = os.getenv("STOCK_LIST") or ((os.getenv("HOME") or "/root") .. "/.myagent_stocks.txt")
    local f = io.open(path, "r")
    if not f then print("自选股表为空: " .. path); os.exit(0) end
    for line in f:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local code, name, asset = resolve(line)
            if not code then
                print(line .. ": 未找到")
            else
                quote(code, name, asset)
            end
        end
    end
    f:close()
else
    local code, name, asset = resolve(cmd)
    if not code then print("未找到: " .. cmd); os.exit(1) end
    quote(code, name, asset)
end
