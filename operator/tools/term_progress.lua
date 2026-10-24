for _, a in ipairs(arg) do
    if a == "--help" or a == "-h" then
        print("用法: term_progress.sh [--to 会话]")
        os.exit(0)
    end
end

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
local dry = os.getenv("PROGRESS_DRY") == "1"
local i = 1
while i <= #arg do
    if arg[i] == "--to" then to = arg[i + 1] or ""; i = i + 2
    else i = i + 1 end
end

local d, err = Xdo.new()
if not d then io.stderr:write("term_progress: " .. err .. "\n"); os.exit(1) end

local class = os.getenv("PROGRESS_CLASS") or "qterminal"
local wins = d:find_class(class)
if #wins == 0 then
    io.stderr:write("没找到 " .. class .. " 窗口\n")
    d:close()
    os.exit(1)
end
local qwin
local pattern = os.getenv("PROGRESS_WINDOW_PATTERN") or "^OC |"
for _, w in ipairs(wins) do
    if (w.name or ""):match(pattern) then qwin = w; break end
end
qwin = qwin or wins[1]
local qid = qwin.id

d:activate(qid)
d:raise(qid)
os.execute("sleep 0.5")
-- 先点标签栏，确保从第一个 tab 开始
d:click(qid, tonumber(os.getenv("PROGRESS_TAB_X")) or 50,
              tonumber(os.getenv("PROGRESS_TAB_Y")) or 39)
os.execute("sleep 0.5")

local stamp = os.date("%Y%m%d_%H%M%S")
local tmpd = "/tmp/myagent_progress_" .. tostring(os.time())
os.execute("mkdir -p " .. q(tmpd))

local first, pics = nil, {}
for n = 1, 12 do
    local title = d:name(qid) or ""
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

    d:activate(qid)
    d:key(0, "ctrl+Page_Down")
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

if dry then
    print("图片: " .. out .. "（dry-run，未发送）")
elseif to ~= "" then
    os.execute(q(DIR .. "/wechat_send_file.sh") .. " " .. q(out) .. " --to " .. q(to))
    print("已发送开发进度（" .. #pics .. " 个 tab）-> " .. to)
else
    os.execute(q(DIR .. "/wechat_send_file.sh") .. " " .. q(out))
    print("已发送开发进度（" .. #pics .. " 个 tab）-> 文件传输助手")
end
