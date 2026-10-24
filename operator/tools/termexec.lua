local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local M = {}

function M.run(cmd, timeout)
    timeout = timeout or 60
    local id = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    local base = "/tmp/myagent_termexec_" .. id
    local script, out, rc = base .. ".sh", base .. ".out", base .. ".rc"
    local title = "myagent-termexec-" .. id

    local f = assert(io.open(script, "w"))
    f:write("#!/bin/bash\n( ", cmd, " ) > ", q(out), " 2>&1\n",
        "echo $? > ", q(rc), "\n")
    f:close()

    os.execute("setsid xterm -T " .. q(title) ..
        " -geometry 120x30 -e bash " .. q(script) ..
        " >/dev/null 2>&1 &")

    local deadline = os.time() + timeout
    local done = false
    while os.time() <= deadline do
        local r = io.open(rc, "r")
        if r then r:close(); done = true; break end
        os.execute("sleep 0.2")
    end

    local result, output = nil, ""
    local of = io.open(out, "r")
    if of then output = of:read("*a") or ""; of:close() end
    if done then
        local rf = io.open(rc, "r")
        if rf then result = tonumber((rf:read("*l") or ""):match("%-?%d+")); rf:close() end
    else
        os.execute("wmctrl -c " .. q(title) .. " 2>/dev/null")
    end

    os.remove(script)
    os.remove(out)
    os.remove(rc)
    return result, output, done
end

return M
