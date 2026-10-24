-- wechat-ocr/lua/xdo_shim.lua — 用 LuaJIT/FFI(libxdo) 接管 xdotool 命令串
-- 目的：微信相关代码里现有的 "xdotool ..." 调用不再启动外部 xdotool，
-- 而是由本模块解析并直接调用 libxdo/X11。
package.path = "/opt/my-agent/operator/tools/?.lua;" .. package.path
local Xdo = require("xdo")

local M = {}
local d

local function display()
    if not d then d = Xdo.new() end
    return d
end

local function tokenize(s)
    local t, i = {}, 1
    while i <= #s do
        local c = s:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c == "'" or c == '"' then
            local q = c
            i = i + 1
            local start = i
            while i <= #s and s:sub(i, i) ~= q do i = i + 1 end
            t[#t + 1] = s:sub(start, i - 1)
            i = i + 1
        else
            local start = i
            while i <= #s and not s:sub(i, i):match("%s") do i = i + 1 end
            t[#t + 1] = s:sub(start, i - 1)
        end
    end
    return t
end

local function geometry_text(id)
    local dd = display()
    id = tonumber(id)
    local g = dd:geometry(id)
    if not g then return "" end
    return string.format("Window %d\n  Position: %d,%d (screen: 0)\n  Geometry: %dx%d\n",
        id, g.x, g.y, g.w, g.h)
end

local function active_id()
    return display():active()
end

local function search_ids(pat, class)
    local dd = display()
    local wins = class and dd:find_class(pat) or dd:find(pat)
    local ids = {}
    for _, w in ipairs(wins) do ids[#ids + 1] = string.format("%d", tonumber(w.id)) end
    return ids
end

local function first_window(pat, class)
    local ids = search_ids(pat, class)
    return ids[1]
end

local function window_action(action, id)
    local dd = display()
    id = tonumber(id)
    if not id then return false end
    if action == "windowactivate" then return dd:activate(id) end
    if action == "windowfocus" then return dd:focus(id) end
    if action == "windowraise" then return dd:raise(id) end
    if action == "windowminimize" then return dd:minimize(id) end
    if action == "windowmap" then return dd:show(id) end
    return false
end

local function parse(cmd)
    cmd = cmd:gsub("^%s*", ""):gsub("%s+2>%s*/dev/null", "")
        :gsub("%s+&>%s*/dev/null", ""):gsub("%s+2>%s*&1", "")
    local background = cmd:match("&%s*$") ~= nil
    cmd = cmd:gsub("%s*&%s*$", ""):gsub("%s*$", "")

    local pipe
    local p = cmd:find("|", 1, true)
    if p then
        pipe = cmd:sub(p + 1):gsub("^%s+", ""):gsub("%s+$", "")
        cmd = cmd:sub(1, p - 1):gsub("%s+$", "")
    end

    local redirect, append
    local base, op, path = cmd:match("^(.-)%s*(>>?)%s*(%S+)%s*$")
    if base then redirect, append, cmd = path, op == ">>", base end

    cmd = cmd:gsub("^%s*xdotool%s+", "")
    local t = tokenize(cmd)
    local verb = t[1]
    local out = ""

    if verb == "search" then
        local pat, class, action
        local i = 2
        while i <= #t do
            if t[i] == "--name" then pat = t[i + 1]; i = i + 2
            elseif t[i] == "--class" then class = true; pat = t[i + 1]; i = i + 2
            elseif t[i] == "windowactivate" or t[i] == "windowfocus" or t[i] == "windowraise"
                or t[i] == "windowminimize" or t[i] == "windowmap" then
                action = t[i]; i = i + 1
            else i = i + 1 end
        end
        local ids = search_ids(pat, class)
        if action then
            if ids[1] then window_action(action, ids[1]) end
        else
            out = table.concat(ids, "\n")
        end
    elseif verb == "getactivewindow" then
        local id = active_id()
        local sub = t[2]
        if id then
            if sub == "getwindowgeometry" then out = geometry_text(id)
            elseif sub == "getwindowname" then out = display():name(id) or ""
            else out = string.format("%d", tonumber(id)) end
        end
    elseif verb == "getwindowgeometry" then
        local id = tonumber(t[2]) or active_id()
        if id then out = geometry_text(id) end
    elseif verb == "getdisplaygeometry" then
        local w, h = display():display_size()
        out = tostring(w) .. " " .. tostring(h)
    elseif verb == "windowactivate" or verb == "windowfocus" or verb == "windowraise"
        or verb == "windowminimize" or verb == "windowmap" then
        local id
        for i = 2, #t do if tonumber(t[i]) then id = tonumber(t[i]); break end end
        if id then window_action(verb, id) end
    elseif verb == "mousemove" then
        local i, x, y, click, button = 2, nil, nil, false, 1
        while i <= #t do
            if t[i] == "--sync" then i = i + 1
            elseif t[i] == "click" then click = true; button = tonumber(t[i + 1]) or 1; i = i + 2
            elseif tonumber(t[i]) then
                if not x then x = tonumber(t[i]) else y = tonumber(t[i]) end
                i = i + 1
            else i = i + 1 end
        end
        if x and y then
            if click then display():click_abs(x, y, button)
            else display():move_abs(x, y) end
        end
    elseif verb == "click" then
        local repeat_count, delay, button = 1, 0, 1
        local i = 2
        while i <= #t do
            if t[i] == "--repeat" then repeat_count = tonumber(t[i + 1]) or 1; i = i + 2
            elseif t[i] == "--delay" then delay = tonumber(t[i + 1]) or 0; i = i + 2
            elseif tonumber(t[i]) then button = tonumber(t[i]); i = i + 1
            else i = i + 1 end
        end
        display():click_current(button, repeat_count, delay)
    elseif verb == "mousedown" or verb == "mouseup" then
        local button = tonumber(t[2]) or 1
        if verb == "mousedown" then display():mouse_down(button)
        else display():mouse_up(button) end
    elseif verb == "key" then
        local wid, seq, i = 0, nil, 2
        while i <= #t do
            if t[i] == "--window" then wid = tonumber(t[i + 1]) or 0; i = i + 2
            elseif t[i] == "--clearmodifiers" then i = i + 1
            else seq = t[i]; i = i + 1 end
        end
        if seq then display():key(wid, seq) end
    elseif verb == "type" then
        local delay, text, wid, i = 0, nil, 0, 2
        while i <= #t do
            if t[i] == "--delay" then delay = tonumber(t[i + 1]) or 0; i = i + 2
            elseif t[i] == "--window" then wid = tonumber(t[i + 1]) or 0; i = i + 2
            else text = t[i]; i = i + 1 end
        end
        if text then
            if text:find("[\128-\255]") then
                local tmp = "/tmp/xdo_shim_type_" .. tostring(os.time()) .. ".txt"
                local f = io.open(tmp, "w")
                if f then f:write(text); f:close() end
                os.execute("xclip -selection clipboard " .. tmp .. " </dev/null >/dev/null 2>&1")
                display():key(wid, "ctrl+v")
                os.remove(tmp)
            else
                display():type(wid, text, delay * 1000)
            end
        end
    end

    if pipe then
        if pipe:match("^head") then
            local n = tonumber(pipe:match("head%s+%-n%s+(%d+)")) or 1
            local lines = {}
            for line in (out .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
            local keep = {}
            for i = 1, math.min(n, #lines) do keep[#keep + 1] = lines[i] end
            out = table.concat(keep, "\n")
        elseif pipe:match("^tail") then
            local n = tonumber(pipe:match("tail%s+%-n%s+(%d+)")) or 1
            local lines = {}
            for line in (out .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
            local keep = {}
            for i = math.max(1, #lines - n + 1), #lines do keep[#keep + 1] = lines[i] end
            out = table.concat(keep, "\n")
        end
    end

    if redirect then
        local mode = append and "a" or "w"
        local f = io.open(redirect, mode)
        if f then f:write(out); f:close() end
        out = ""
    end

    return 0, out, background
end

local function fake_handle(out)
    local pos = 1
    return {
        read = function(_, fmt)
            if fmt == "*a" then
                local s = out:sub(pos); pos = #out + 1; return s
            elseif fmt == "*l" then
                if pos > #out then return nil end
                local nl = out:find("\n", pos, true)
                local s
                if nl then s = out:sub(pos, nl - 1); pos = nl + 1
                else s = out:sub(pos); pos = #out + 1 end
                return s
            end
        end,
        lines = function()
            local p = 1
            return function()
                if p > #out then return nil end
                local nl = out:find("\n", p, true)
                local s
                if nl then s = out:sub(p, nl - 1); p = nl + 1
                else s = out:sub(p); p = #out + 1 end
                return s
            end
        end,
        close = function() return true end,
    }
end

function M.execute(cmd)
    local rc, out, bg = parse(cmd)
    if not bg and out ~= "" then io.write(out) end
    return rc
end

function M.capture(cmd)
    local _, out = parse(cmd)
    return out
end

function M.popen(cmd)
    local _, out = parse(cmd)
    return fake_handle(out)
end

function M.install()
    if M.installed then return end
    local real_execute = os.execute
    local real_popen = io.popen
    os.execute = function(cmd)
        if type(cmd) == "string" and cmd:match("^%s*xdotool%s") then
            return M.execute(cmd)
        end
        return real_execute(cmd)
    end
    M.installed = true
    io.popen = function(cmd, mode)
        if type(cmd) == "string" and cmd:match("^%s*xdotool%s") then
            return M.popen(cmd)
        end
        return real_popen(cmd, mode)
    end
end

return M
