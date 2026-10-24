local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local Xdo = require("xdo")

local TO = "文件传输助手"
local APP = ""
local i = 1
while i <= #arg do
    if arg[i] == "--to" then TO = arg[i + 1] or TO; i = i + 2
    elseif arg[i] == "--app" then APP = arg[i + 1] or ""; i = i + 2
    else i = i + 1 end
end

local d, err = Xdo.new()
if not d then io.stderr:write("wechat_shot: ", err, "\n"); os.exit(1) end

local function q(s) return string.format("%q", s) end
local function sleep_ms(ms) os.execute("sleep " .. string.format("%.3f", ms / 1000)) end

local out = "/tmp/myagent_shot_" .. os.time() .. ".png"
local wins = d:windows()

local function capture()
    if os.execute("import -window root " .. q(out) .. " 2>/dev/null") ~= 0 then return false end
    local f = io.open(out, "rb")
    if not f then return false end
    local ok = f:seek("end") > 0
    f:close()
    return ok
end

local function capture_desktop()
    local hidden = {}
    for _, w in ipairs(wins) do
        local n = (w.name or ""):lower()
        if n ~= "" and not n:find("pcmanfm%-desktop", 1, true)
           and not n:find("lxqt", 1, true) then
            local id = tostring(w.id)
            if os.execute("wmctrl -i -r " .. q(id) .. " -b add,hidden 2>/dev/null") == 0 then
                hidden[#hidden + 1] = id
            end
        end
    end
    sleep_ms(800)
    local ok = capture()
    for _, id in ipairs(hidden) do
        os.execute("wmctrl -i -r " .. q(id) .. " -b remove,hidden 2>/dev/null")
        os.execute("wmctrl -i -a " .. q(id) .. " 2>/dev/null")
    end
    return ok
end

if APP ~= "" then
    local aliases = {
        ["助手"]="agent", ["ai助手"]="agent", ["myagent"]="agent", ["my-agent"]="agent", ["agent"]="agent",
        ["浏览器"]="chrome", ["谷歌浏览器"]="chrome", ["chrome"]="chrome",
        ["终端"]="qterminal", ["命令行"]="qterminal", ["terminal"]="qterminal",
        ["文件管理器"]="pcmanfm", ["文件夹"]="pcmanfm", ["文件"]="pcmanfm",
    }
    local key = APP:lower()
    key = aliases[key] or key
    local target
    for _, w in ipairs(wins) do
        local n = (w.name or ""):lower()
        if n:find(key, 1, true) then target = w; break end
    end
    if target then
        d:activate(target.id)
        sleep_ms(900)
        if not capture() then
            io.stderr:write("截图失败\n"); d:close(); os.exit(1)
        end
    else
        io.stderr:write("未找到应用 '" .. APP .. "'，改截桌面\n")
        if not capture_desktop() then
            io.stderr:write("截图失败\n"); d:close(); os.exit(1)
        end
    end
else
    if not capture_desktop() then
        io.stderr:write("截图失败\n"); d:close(); os.exit(1)
    end
end

d:close()

if os.getenv("WECHAT_SHOT_DRY") == "1" then
    print(out)
    os.exit(0)
end

local cmd = q(DIR .. "/wechat_send_file.sh") .. " " .. q(out) .. " --to " .. q(TO)
if os.execute(cmd) ~= 0 then
    io.stderr:write("发送微信失败\n")
    os.exit(1)
end
print(out)
