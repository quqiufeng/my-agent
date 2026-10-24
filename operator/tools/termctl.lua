local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local Xdo = require("xdo")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function sleep_s(sec)
    os.execute("sleep " .. tostring(sec))
end

local function size(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local n = f:seek("end") or 0
    f:close()
    return n
end

local TAB_X = tonumber(os.getenv("TERMCTL_TAB_X")) or 60
local TAB_Y = tonumber(os.getenv("TERMCTL_TAB_Y")) or 18
local INPUT_X = tonumber(os.getenv("TERMCTL_INPUT_X")) or 80
local INPUT_Y = tonumber(os.getenv("TERMCTL_INPUT_Y")) or 778
local MAX_TABS = tonumber(os.getenv("TERMCTL_MAX_TABS")) or 12

local d = Xdo.new()
if not d then io.stderr:write("找不到 X display\n"); os.exit(1) end
local wins = d:find_class("qterminal")
if #wins == 0 then
    io.stderr:write("找不到 qterminal 窗口\n")
    d:close()
    os.exit(1)
end
local wid = wins[1].id

local function focus()
    d:activate(wid)
    d:raise(wid)
    sleep_s(0.3)
end

local function goto_tab(n)
    focus()
    d:click(wid, TAB_X, TAB_Y)
    sleep_s(0.5)
    for _ = 2, n do
        d:key(0, "ctrl+Page_Down")
        sleep_s(0.35)
    end
end

local function cmd_tabs()
    focus()
    d:click(wid, TAB_X, TAB_Y)
    sleep_s(0.5)
    local first, lines, n = nil, {}, 0
    while n < MAX_TABS do
        n = n + 1
        local t = d:name(wid) or ""
        lines[#lines + 1] = "tab" .. n .. ": " .. t
        if first == nil then first = t end
        d:key(0, "ctrl+Page_Down")
        sleep_s(0.4)
        if (d:name(wid) or "") == first then break end
    end
    print(n)
    print(table.concat(lines, "\n"))
end

local function send_file(path, to)
    local cmd = q(DIR .. "/wechat_send_file.sh") .. " " .. q(path)
    if to and to ~= "" then cmd = cmd .. " --to " .. q(to) end
    return os.execute(cmd) == 0
end

local function cmd_shot(args)
    local n, to
    local i = 1
    while i <= #args do
        if args[i] == "--to" then to = args[i + 1]; i = i + 2
        else n = tonumber(args[i]); i = i + 1 end
    end
    if n then goto_tab(n) end
    focus()
    local out = "/tmp/termctl_shot_" .. tostring(os.time()) .. ".png"
    if os.execute("import -window " .. tostring(wid) .. " " .. q(out) .. " 2>/dev/null") ~= 0
        or size(out) == 0 then
        io.stderr:write("截图失败\n")
        d:close()
        os.exit(1)
    end
    if os.getenv("TERMCTL_DRY") ~= "1" then
        if not send_file(out, to) then
            io.stderr:write("发送失败\n")
            d:close()
            os.exit(1)
        end
    end
    print(out)
end

local function cmd_send(args)
    local n = tonumber(args[1])
    local text = args[2] or ""
    local enter = args[3] ~= "--no-enter"
    if not n or text == "" then
        io.stderr:write("用法: termctl.sh send <N> \"<指令>\" [--no-enter]\n")
        d:close()
        os.exit(2)
    end
    text = text:gsub("\n", " ")
    goto_tab(n)
    d:click(wid, INPUT_X, INPUT_Y)
    sleep_s(0.4)
    os.execute("printf '%s' " .. q(text) .. " | xclip -selection clipboard -l 1 >/dev/null 2>&1")
    d:key(0, "ctrl+shift+v")
    sleep_s(0.4)
    if enter then
        d:key(0, "Return")
        print("已发送到 tab" .. n .. ": " .. text)
    else
        print("已注入(未回车)到 tab" .. n .. ": " .. text)
    end
end

local cmd = arg[1] or "tabs"
local rest = {}
for i = 2, #arg do rest[#rest + 1] = arg[i] end

if cmd == "tabs" then
    cmd_tabs()
elseif cmd == "shot" then
    cmd_shot(rest)
elseif cmd == "send" then
    cmd_send(rest)
elseif cmd == "goto" then
    local n = tonumber(rest[1]) or 1
    goto_tab(n)
    print("已切到 tab" .. n)
else
    io.stderr:write("用法: termctl.sh tabs | shot [N] [--to 会话] | send <N> \"<指令>\" [--no-enter]\n")
    d:close()
    os.exit(2)
end

d:close()
