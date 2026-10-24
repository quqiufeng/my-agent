local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ffi = require("ffi")
ffi.cdef[[int getpid(void);]]
local PID = ffi.C.getpid()
local SEQ = 0
local JOBS = os.getenv("BGJOB_DIR") or "/tmp/myagent_jobs"

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function ensure()
    os.execute("mkdir -p " .. q(JOBS))
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local s = f:read("*a") or ""
    f:close()
    return s
end

local function write_file(path, s)
    local f = io.open(path, "w")
    if f then f:write(s); f:close() end
end

local function new_id()
    SEQ = SEQ + 1
    return os.date("%Y%m%d_%H%M%S") .. "_" .. tostring(PID) .. "_" .. tostring(SEQ)
end

local M = {}

function M.spawn(script, args, name)
    ensure()
    local id = new_id()
    local log = JOBS .. "/" .. id .. ".log"
    local pidf = JOBS .. "/" .. id .. ".pid"
    local parts = { "setsid", "env", "BG_WORKER=1", "luajit", q(script) }
    for _, a in ipairs(args or {}) do parts[#parts + 1] = q(a) end
    local cmd = table.concat(parts, " ") .. " </dev/null >" .. q(log) ..
        " 2>&1 & echo $! >" .. q(pidf)
    os.execute(cmd)
    write_file(JOBS .. "/" .. id .. ".name", name or "job")
    local pid = tonumber((read_file(pidf):match("%d+")))
    return { id = id, log = log, pid = pid, name = name or "job" }
end

function M.spawn_self(args, name)
    local script = arg[0]
    if not script or not script:match("%.lua$") then
        error("spawn_self: arg[0] 不是 lua 脚本")
    end
    return M.spawn(script, args, name)
end

function M.pid(id)
    return tonumber((read_file(JOBS .. "/" .. id .. ".pid"):match("%d+")))
end

function M.log(id)
    return JOBS .. "/" .. id .. ".log"
end

function M.status(id)
    local pid = M.pid(id)
    if not pid then return "unknown" end
    if os.execute("kill -0 " .. tostring(pid) .. " 2>/dev/null") == 0 then
        return "running"
    end
    return "done"
end

function M.tail(id, n)
    n = n or 30
    local s = read_file(M.log(id))
    if s == "" then return "" end
    local lines = {}
    for line in (s .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    local out = {}
    for i = math.max(1, #lines - n + 1), #lines do out[#out + 1] = lines[i] end
    return table.concat(out, "\n")
end

function M.stop(id)
    local pid = M.pid(id)
    if not pid then return false, "no pid" end
    os.execute("kill " .. tostring(pid) .. " 2>/dev/null")
    return true
end

function M.list()
    ensure()
    local out = {}
    local p = io.popen("ls -1 " .. q(JOBS) .. "/*.pid 2>/dev/null | sort")
    if not p then return out end
    for line in p:lines() do
        local id = line:match("([^/]+)%.pid$")
        if id then
            local name = (read_file(JOBS .. "/" .. id .. ".name")):gsub("%s+$", "")
            local st = M.status(id)
            local log = JOBS .. "/" .. id .. ".log"
            local sz = 0
            local lf = io.open(log, "rb")
            if lf then sz = lf:seek("end") or 0; lf:close() end
            out[#out + 1] = string.format("%s\t%s\t%s\t%d B\t%s", id, st, name, sz, log)
        end
    end
    p:close()
    return out
end

return M
