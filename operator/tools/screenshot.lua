local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local Xdo = require("xdo")

local home = os.getenv("HOME") or "/root"
local conf_path = home .. "/.config/screengrab/screengrab.conf"
local save_dir = home .. "/Pictures"

local f = io.open(conf_path, "r")
if f then
    for line in f:lines() do
        local d = line:match("^defDir=(.+)$")
        if d and #d > 0 then save_dir = d end
    end
    f:close()
end
os.execute("mkdir -p " .. string.format("%q", save_dir) .. " 2>/dev/null")

local function q(s) return string.format("%q", s) end

local function newest()
    local p = io.popen("ls -t " .. q(save_dir) .. "/*.png " .. q(save_dir) .. "/*.jpg 2>/dev/null | head -1")
    local s = p:read("*l")
    p:close()
    return s
end

local function mtime(path)
    local p = io.popen("stat -c %Y " .. q(path) .. " 2>/dev/null")
    local s = p:read("*l")
    p:close()
    return tonumber(s) or 0
end

local old = newest()
local old_mt = old and mtime(old) or 0

local d, err = Xdo.new()
if not d then io.stderr:write("screenshot: ", err, "\n"); os.exit(1) end
d:key(0, "Print", 12000)
d:close()

local now_path
for _ = 1, 12 do
    os.execute("sleep 0.5")
    local n = newest()
    if n and (n ~= old or mtime(n) > old_mt) then now_path = n; break end
end

os.execute("wmctrl -c ScreenGrab 2>/dev/null")

if now_path then
    local out = arg[1]
    if out then
        os.execute("cp -f " .. q(now_path) .. " " .. q(out))
        print(out)
    else
        print(now_path)
    end
    os.exit(0)
end

local out = arg[1] or ("/tmp/myagent_shot_" .. os.date("%Y%m%d_%H%M%S") .. ".png")
if os.execute("import -window root " .. q(out) .. " 2>/dev/null") == 0 then
    print(out)
    os.exit(0)
end
io.stderr:write("截屏失败\n")
os.exit(1)
