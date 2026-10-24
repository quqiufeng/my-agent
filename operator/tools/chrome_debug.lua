local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local port = tonumber(arg[1]) or 9222
local home = os.getenv("HOME") or "/root"
local deb = home .. "/.chrome-debug-profile"

local function port_open()
    return os.execute("ss -ltn 2>/dev/null | grep -q ':" .. tostring(port) .. " '") == 0
end

if port_open() then
    print("Chrome 已在端口 " .. port .. " 运行")
    os.exit(0)
end

print("同步 profile...")
os.execute("mkdir -p " .. q(deb .. "/Default"))
os.execute("rsync -a " .. q(home .. "/.config/google-chrome/Local State") .. " " .. q(deb .. "/") .. " 2>/dev/null")
os.execute("rsync -a --exclude 'Cache/' --exclude 'Code Cache/' --exclude 'GPUCache/' " ..
    "--exclude 'ShaderCache/' --exclude 'GrShaderCache/' --exclude 'Service Worker/' " ..
    "--exclude 'Crash Reports/' " ..
    q(home .. "/.config/google-chrome/Default/") .. " " .. q(deb .. "/Default/") .. " 2>/dev/null")

local p = io.popen("ps -eo pid,comm | awk '$2==\"chrome\"{print $1}'")
local pids = {}
if p then
    for line in p:lines() do if line:match("^%d+$") then pids[#pids + 1] = line end end
    p:close()
end
for _, pid in ipairs(pids) do os.execute("kill -9 " .. pid .. " 2>/dev/null") end
os.execute("sleep 2")

local xa = ""
local pp = io.popen("pgrep -x pcmanfm-qt | head -1")
local pid = pp and pp:read("*l") or nil
if pp then pp:close() end
if pid and pid ~= "" then
    local ep = io.popen("tr '\\0' '\\n' < /proc/" .. pid .. "/environ 2>/dev/null | sed -n 's/^XAUTHORITY=//p'")
    xa = ep and (ep:read("*l") or "") or ""
    if ep then ep:close() end
end

local cmd = "setsid env DISPLAY=:0"
if xa ~= "" then cmd = cmd .. " XAUTHORITY=" .. q(xa) end
cmd = cmd .. " google-chrome --remote-debugging-port=" .. tostring(port) ..
    " --user-data-dir=" .. q(deb) ..
    " --no-first-run --no-default-browser-check" ..
    " >/tmp/opencode/chrome_debug.log 2>&1 </dev/null &"
os.execute(cmd)

os.execute("sleep 5")
if port_open() then
    print("Chrome 已启动（端口 " .. port .. "），可直接用 MCP")
else
    io.stderr:write("启动失败，见 /tmp/opencode/chrome_debug.log\n")
    os.exit(1)
end
