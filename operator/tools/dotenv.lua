local ffi = require("ffi")

ffi.cdef[[
int setenv(const char *name, const char *value, int overwrite);
]]

local M = {}

local function unquote(v)
    local q = v:sub(1, 1)
    if q == "'" or q == '"' then
        local e = v:find(q, 2, true)
        if e then
            local inner = v:sub(2, e - 1)
            if q == "'" then
                inner = inner:gsub("'\\''", "'")
            else
                inner = inner:gsub('\\"', '"'):gsub("\\\\", "\\")
            end
            return inner
        end
    end
    return (v:gsub("%s+#.*$", ""):gsub("%s+$", ""))
end

function M.load(path)
    path = path or (((os.getenv("HOME") or "/root")) .. "/.env")
    local f = io.open(path, "r")
    if not f then return false end
    for line in f:lines() do
        line = line:gsub("\r$", "")
        if line:match("%S") and not line:match("^%s*#") then
            local k, v = line:match("^%s*export%s+([%w_]+)%s*=%s*(.*)$")
            if not k then k, v = line:match("^%s*([%w_]+)%s*=%s*(.*)$") end
            if k and v then ffi.C.setenv(k, unquote(v), 1) end
        end
    end
    f:close()
    return true
end

return M
