local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ENVF = os.getenv("ENVF") or ((os.getenv("HOME") or "/root") .. "/.env")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function read_lines()
    local lines = {}
    local f = io.open(ENVF, "r")
    if not f then return lines end
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()
    return lines
end

local function write_lines(lines)
    local f = assert(io.open(ENVF, "w"))
    for _, line in ipairs(lines) do f:write(line, "\n") end
    f:close()
end

local function unquote(v)
    local q = v:sub(1, 1)
    if (q == "'" or q == '"') and v:sub(-1) == q then
        local inner = v:sub(2, -2)
        if q == "'" then inner = inner:gsub("'\\''", "'") end
        return inner
    end
    return v
end

local function getkey(key)
    for _, line in ipairs(read_lines()) do
        if line:sub(1, #key + 1) == key .. "=" then
            return unquote(line:sub(#key + 2))
        end
    end
    return ""
end

local function setkey(key, value)
    local lines = read_lines()
    local out = {}
    for _, line in ipairs(lines) do
        if line:sub(1, #key + 1) ~= key .. "=" then out[#out + 1] = line end
    end
    out[#out + 1] = key .. "='" .. value:gsub("'", "'\\''") .. "'"
    write_lines(out)
end

local cmd = arg[1] or ""

if cmd == "save" then
    local host, key = arg[2], arg[3]
    if not host or host == "" or not key or key == "" then
        io.stderr:write("用法: cookie.sh save <域名> <ENVKEY>\n")
        os.exit(2)
    end
    local p = io.popen("node " .. q(DIR .. "/cookies.js") .. " " .. q(host))
    local v = p and p:read("*a") or ""
    if p then p:close() end
    if v == "" then
        io.stderr:write("未从 Chrome 取到 cookie（确认已登录且 Chrome 在跑）\n")
        os.exit(1)
    end
    setkey(key, v)
    local n = 0
    for part in v:gmatch("[^;]+") do
        if part:find("=", 1, true) then n = n + 1 end
    end
    print("已保存 " .. key .. "（" .. n .. " 项）→ " .. ENVF)
elseif cmd == "set" then
    local key = arg[2]
    if not key or key == "" then io.stderr:write("缺 ENVKEY\n"); os.exit(2) end
    local value = table.concat(arg, " ", 3)
    setkey(key, value)
    print("已写入 " .. key)
elseif cmd == "get" then
    local key = arg[2]
    if not key or key == "" then io.stderr:write("缺 ENVKEY\n"); os.exit(2) end
    print(getkey(key))
elseif cmd == "list" then
    for _, line in ipairs(read_lines()) do
        local k = line:match("^([A-Z0-9_]+_COOKIE)=")
        if k then print(k) end
    end
else
    io.stderr:write("用法: cookie.sh save <域名> <ENVKEY> | set <ENVKEY> <值> | get <ENVKEY> | list\n")
    os.exit(2)
end
