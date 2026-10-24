local Xdo = require("xdo")

local SRC = debug.getinfo(1, "S").source:gsub("^@", "")
local DIR = SRC:match("^(.*)/") or "."

local M = {}

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M.open(url)
    os.execute("setsid google-chrome " .. q(url) .. " >/dev/null 2>&1 &")
    os.execute("sleep 8")

    local d = Xdo.new()
    if d then
        local wins = d:find("Google Chrome")
        if #wins == 0 then wins = d:find("Chrome") end
        if #wins > 0 then d:activate(wins[1].id) end
        d:close()
    end
    os.execute("sleep 3")
end

function M.capture(prefix)
    local out = prefix .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".png"
    if os.execute("import -window root " .. q(out) .. " 2>/dev/null") ~= 0 then
        return nil
    end
    local f = io.open(out, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    if not size or size == 0 then os.remove(out); return nil end
    return out
end

function M.send(path, to)
    local cmd = q(DIR .. "/wechat_send_file.sh") .. " " .. q(path)
    if to and to ~= "" then cmd = cmd .. " --to " .. q(to) end
    return os.execute(cmd) == 0
end

return M
