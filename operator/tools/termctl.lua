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

-- 与 ~/opencode_retry.sh 对齐：标签栏 50,39；输入框按窗口宽高算
local TAB_X = tonumber(os.getenv("TERMCTL_TAB_X")) or 50
local TAB_Y = tonumber(os.getenv("TERMCTL_TAB_Y")) or 39
local MAX_TABS = tonumber(os.getenv("TERMCTL_MAX_TABS")) or 12
local PATTERN = os.getenv("TERMCTL_WINDOW_PATTERN") or "^OC |"

local d = Xdo.new()
if not d then io.stderr:write("找不到 X display\n"); os.exit(1) end

local function find_term()
    local wins = d:find_class("qterminal")
    for _, w in ipairs(wins) do
        if (w.name or ""):match(PATTERN) then return w end
    end
    return wins[1]
end

local win = find_term()
if not win then
    io.stderr:write("找不到 qterminal/opencode 窗口\n")
    d:close()
    os.exit(1)
end
local wid = win.id

local function focus()
    d:activate(wid)
    d:raise(wid)
    sleep_s(0.3)
end

local function goto_tab(n)
    n = tonumber(n) or 1
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

local function read_clip()
    local p = io.popen("timeout 1 xclip -o -selection clipboard 2>/dev/null")
    local s = p and (p:read("*a") or "") or ""
    if p then p:close() end
    return s
end

local function set_clip(text)
    local f = io.open("/tmp/termctl_clip.txt", "w")
    if not f then return false end
    f:write(text or ""); f:close()
    local ok = os.execute("xclip -selection clipboard -l 1 < /tmp/termctl_clip.txt >/dev/null 2>&1") == 0
    os.remove("/tmp/termctl_clip.txt")
    return ok
end

local function cmd_send(args)
    local n = tonumber(args[1])
    local enter = true
    local parts = {}
    for i = 2, #args do
        if args[i] == "--no-enter" then enter = false
        else parts[#parts + 1] = args[i] end
    end
    local text = table.concat(parts, " ")
    if not n or text == "" then
        io.stderr:write("用法: termctl.sh send <N> \"<指令>\" [--no-enter]\n")
        d:close()
        os.exit(2)
    end
    text = text:gsub("\n", " ")
    goto_tab(n)
    local g = d:geometry(wid) or {}
    local ix = tonumber(os.getenv("TERMCTL_INPUT_X")) or math.floor((g.w or 0) / 5)
    local iy = tonumber(os.getenv("TERMCTL_INPUT_Y")) or math.max(0, (g.h or 0) - 120)
    d:click(wid, ix, iy)
    sleep_s(0.4)
    local old = read_clip()
    set_clip(text)
    d:key(0, "ctrl+shift+v")
    sleep_s(0.4)
    if old ~= "" then set_clip(old) end
    if enter then
        d:key(0, "Return")
        print("已发送到 tab" .. n .. ": " .. text)
    else
        print("已注入(未回车)到 tab" .. n .. ": " .. text)
    end
    if os.getenv("TERMCTL_MINIMIZE") == "1" then
        sleep_s(0.5)
        d:minimize(wid)
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
