local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
require("dotenv").load(os.getenv("ECOVACS_ENV") or ((os.getenv("HOME") or "/root") .. "/.env"))

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local bin = os.getenv("VACUUM_BIN") or "/opt/my-agent/agentkit/native_vacuum/vacuum"
local f = io.open(bin, "rb")
local cmd
if f then
    f:close()
    cmd = q(bin)
else
    local py = os.getenv("VACUUM_PYTHON") or "/data/venv/bin/python"
    cmd = q(py) .. " " .. q("/opt/my-agent/agentkit/tools/vacuum.py")
end

for i = 1, #arg do cmd = cmd .. " " .. q(arg[i]) end

local rc = os.execute(cmd)
os.exit(rc == 0 and 0 or 1)
