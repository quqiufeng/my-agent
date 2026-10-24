local DIR = (arg and arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path

require("dotenv").load(os.getenv("EZVIZ_ENV") or ((os.getenv("HOME") or "/root") .. "/.env"))
local cjson = require("cjson")
local M = {}

local API = "https://open.ys7.com"

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function urlencode(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function post(url, fields)
    local parts = {}
    for _, f in ipairs(fields) do
        parts[#parts + 1] = "-d " .. q((f[1] or "") .. "=" .. urlencode(f[2] or ""))
    end
    local p = io.popen("curl -s -X POST " .. q(url) .. " " .. table.concat(parts, " ") .. " 2>/dev/null")
    local raw = p and p:read("*a") or ""
    if p then p:close() end
    local ok, res = pcall(cjson.decode, raw)
    return ok and res or nil, raw
end

function M.serial(kind)
    if kind == "menkou" or kind == "门口" or kind == "door" then
        return "815311181", "/tmp/myagent_door.url"
    end
    return "802657358", "/tmp/myagent_ezviz.url"
end

function M.refresh(serial, out)
    serial = serial or "802657358"
    out = out or "/tmp/myagent_ezviz.url"
    local appkey = os.getenv("EZVIZ_APPKEY") or ""
    local secret = os.getenv("EZVIZ_APPSECRET") or ""
    if appkey == "" or secret == "" then
        return nil, "缺 EZVIZ_APPKEY / EZVIZ_APPSECRET（~/.env）"
    end

    local token_res = post(API .. "/api/lapp/token/get", {
        { "appKey", appkey }, { "appSecret", secret },
    })
    local tok = token_res and token_res.data and token_res.data.accessToken or nil
    if not tok or tok == "" then return nil, "取 token 失败" end

    local function live()
        return post(API .. "/api/lapp/v2/live/address/get", {
            { "accessToken", tok }, { "deviceSerial", serial }, { "channelNo", "1" },
            { "protocol", os.getenv("EZVIZ_PROTOCOL") or "2" },
            { "quality", "1" }, { "expireTime", "604800" },
        })
    end

    local res, raw = live()
    local code = res and res.code or nil
    if tostring(code) == "60019" then
        local vc = os.getenv("EZVIZ_CODE_" .. serial) or ""
        if vc ~= "" then
            post(API .. "/api/lapp/device/encrypt/off", {
                { "accessToken", tok }, { "deviceSerial", serial }, { "validateCode", vc },
            })
            res, raw = live()
            code = res and res.code or nil
        end
    end
    if tostring(code) ~= "200" then
        return nil, raw ~= "" and raw or "取流失败"
    end
    local url = res and res.data and res.data.url or nil
    if not url or url == "" or url == "null" then return nil, "返回空地址" end
    local f = assert(io.open(out, "w"))
    f:write(url, "\n")
    f:close()
    return url
end

return M
