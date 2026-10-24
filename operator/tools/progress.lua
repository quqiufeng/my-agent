local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local Xdo = require("xdo")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function size(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local n = f:seek("end") or 0
    f:close()
    return n
end

local to = os.getenv("WECHAT_TO") or ""
local i = 1
while i <= #arg do
    if arg[i] == "--to" then to = arg[i + 1] or ""; i = i + 2
    else i = i + 1 end
end

local d, err = Xdo.new()
if not d then io.stderr:write("progress: " .. err .. "\n"); os.exit(1) end

local class = os.getenv("PROGRESS_CLASS") or "qterminal"
local wins = d:find_class(class)
if #wins == 0 then
    io.stderr:write("没找到 " .. class .. " 窗口\n")
    d:close()
    os.exit(1)
end
local qid = wins[1].id

d:activate(qid)
os.execute("sleep 0.9")

local stamp = os.date("%Y%m%d_%H%M%S")
local tmpd = "/tmp/myagent_progress_" .. tostring(os.time())
os.execute("mkdir -p " .. q(tmpd))

local first, pics = nil, {}
for n = 1, 12 do
    local active = d:active()
    local title = active and d:name(active) or ""
    if first ~= nil and title == first then break end
    if first == nil then first = title end

    local f = string.format("%s/tab_%02d.png", tmpd, n)
    os.execute("import -window " .. tostring(qid) .. " " .. q(f) .. " 2>/dev/null")
    if size(f) > 0 then
        pics[#pics + 1] = f
        local label = title:gsub("^OC | ", "")
        print(string.format("tab%d [%s]", n, label))
    else
        os.remove(f)
    end

    d:key(0, "ctrl+Next")
    os.execute("sleep 0.7")
end
d:close()

if #pics == 0 then
    io.stderr:write("没截到图（qterminal 无 tab？）\n")
    os.execute("rm -rf " .. q(tmpd))
    os.exit(1)
end

local out = "/tmp/myagent_progress_" .. stamp .. ".png"
if #pics == 1 then
    os.execute("cp " .. q(pics[1]) .. " " .. q(out))
else
    local cmd = "montage"
    for _, p in ipairs(pics) do cmd = cmd .. " " .. q(p) end
    cmd = cmd .. " -tile 1x -geometry +0+8 -background '#202020' " .. q(out) .. " 2>/dev/null"
    if os.execute(cmd) ~= 0 then os.execute("cp " .. q(pics[1]) .. " " .. q(out)) end
end
os.execute("rm -rf " .. q(tmpd))

if to ~= "" then
    os.execute(q(DIR .. "/wechat_send_file.sh") .. " " .. q(out) .. " --to " .. q(to))
    print("已发送开发进度（" .. #pics .. " 个 tab）-> " .. to)
else
    os.execute(q(DIR .. "/wechat_send_file.sh") .. " " .. q(out))
    print("已发送开发进度（" .. #pics .. " 个 tab）-> 文件传输助手")
end
