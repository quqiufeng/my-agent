local DIR = (arg[0] or ""):match("^(.*)/") or "."

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function run(script, args)
    local parts = { "luajit", q(DIR .. "/" .. script) }
    for _, a in ipairs(args or {}) do parts[#parts + 1] = q(a) end
    return os.execute(table.concat(parts, " "))
end

local cmd = arg[1] or ""
local rest = {}
for i = 2, #arg do rest[#rest + 1] = arg[i] end

if cmd == "say" then
    os.exit(run("say.lua", rest) == 0 and 0 or 1)
elseif cmd == "listen" then
    os.exit(run("listen.lua", rest) == 0 and 0 or 1)
elseif cmd == "tutor" or cmd == "english" then
    os.exit(run("tutor.lua", rest) == 0 and 0 or 1)
elseif cmd == "once" then
    local a = { "--once", "--no-forward" }
    for _, v in ipairs(rest) do a[#a + 1] = v end
    os.exit(run("listen.lua", a) == 0 and 0 or 1)
elseif cmd == "test" then
    local text = table.concat(rest, " ")
    if text == "" then text = "你好，我是星期五，语音模块自检正常。" end
    os.exit(run("say.lua", { text }) == 0 and 0 or 1)
elseif cmd == "camera" then
    local parts = { q(DIR .. "/camera.sh") }
    for _, a in ipairs(rest) do parts[#parts + 1] = q(a) end
    os.exit(os.execute(table.concat(parts, " ")) == 0 and 0 or 1)
elseif cmd == "app" or cmd == "ui" then
    local parts = { q(DIR .. "/app.sh") }
    for _, a in ipairs(rest) do parts[#parts + 1] = q(a) end
    os.exit(os.execute(table.concat(parts, " ")) == 0 and 0 or 1)
elseif cmd == "orb" or cmd == "ball" then
    local parts = { q(DIR .. "/orb.sh") }
    for _, a in ipairs(rest) do parts[#parts + 1] = q(a) end
    os.exit(os.execute(table.concat(parts, " ")) == 0 and 0 or 1)
else
    io.stderr:write("用法: voice.sh {say <文本>|listen|once|test|camera|app|orb}\n")
    os.exit(2)
end
