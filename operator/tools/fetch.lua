local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
require("dotenv").load()

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local url, ckkey, post, save, referer = nil, nil, nil, nil, nil
local json = false
local ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36"
local headers = {}

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--cookie" then ckkey = arg[i + 1]; i = i + 2
    elseif a == "--post" then post = arg[i + 1]; i = i + 2
    elseif a == "--save" then save = arg[i + 1]; i = i + 2
    elseif a == "--referer" then referer = arg[i + 1]; i = i + 2
    elseif a == "--header" then headers[#headers + 1] = arg[i + 1]; i = i + 2
    elseif a == "--ua" then ua = arg[i + 1]; i = i + 2
    elseif a == "--json" then json = true; i = i + 1
    else
        if not url then url = a end
        i = i + 1
    end
end

if not url or url == "" then
    io.stderr:write("用法: fetch.sh <url> [--cookie ENVKEY] [--post DATA] [--json] [--save FILE] [--referer URL] [--header 'K: V']\n")
    os.exit(2)
end

local args = { "-sSL", "--max-time", "30", "-A", ua }
if referer and referer ~= "" then
    args[#args + 1] = "-e"; args[#args + 1] = referer
end
if ckkey and ckkey ~= "" then
    local ck = os.getenv(ckkey)
    if not ck or ck == "" then
        io.stderr:write("无 cookie: " .. ckkey .. "（先 cookie.sh save <域名> " .. ckkey .. "）\n")
        os.exit(3)
    end
    args[#args + 1] = "-H"; args[#args + 1] = "Cookie: " .. ck
end
if post then
    if json then args[#args + 1] = "-H"; args[#args + 1] = "Content-Type: application/json" end
    args[#args + 1] = "--data"; args[#args + 1] = post
end
for _, h in ipairs(headers) do
    args[#args + 1] = "-H"; args[#args + 1] = h
end

local parts = { "curl" }
for _, a in ipairs(args) do parts[#parts + 1] = q(a) end
if save and save ~= "" then
    parts[#parts + 1] = "-o"; parts[#parts + 1] = q(save)
    parts[#parts + 1] = q(url)
    local rc = os.execute(table.concat(parts, " "))
    if rc == 0 then print(save) end
    os.exit(rc == 0 and 0 or 1)
else
    parts[#parts + 1] = q(url)
    local rc = os.execute(table.concat(parts, " "))
    os.exit(rc == 0 and 0 or 1)
end
