local DIR = (arg[0] or ""):match("^(.*)/") or "."

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local iso = os.getenv("ISO_FLUTTER") or ((os.getenv("HOME") or "/root") .. "/iso_flutter")
iso = iso .. "/bin/iso.sh"
if os.execute("test -x " .. q(iso)) ~= 0 then
    io.stderr:write("找不到等距图引擎入口：" .. iso .. "（~/iso_flutter/bin/iso.sh）\n")
    os.exit(1)
end

local to, send, args = "", true, {}
local i = 1
while i <= #arg do
    if arg[i] == "--to" then
        if not arg[i + 1] then io.stderr:write("--to 缺少会话名\n"); os.exit(2) end
        to = arg[i + 1]; i = i + 2
    elseif arg[i] == "--no-send" then
        send = false; i = i + 1
    else
        args[#args + 1] = arg[i]; i = i + 1
    end
end

local parts = { q(iso) }
for _, a in ipairs(args) do parts[#parts + 1] = q(a) end
local p = io.popen(table.concat(parts, " ") .. " 2>&1")
local output = p and p:read("*a") or ""
local ok = p and p:close() or nil
if not ok then
    io.stderr:write(output)
    os.exit(1)
end

local file = output:match("([^\n]+)%s*$")
if not file then
    io.stderr:write("未生成文件（输出：" .. output .. "）\n")
    os.exit(1)
end
file = file:gsub("^%s+", ""):gsub("%s+$", "")

local f = io.open(file, "rb")
if not f then
    io.stderr:write("未生成文件（输出：" .. output .. "）\n")
    os.exit(1)
end
f:close()
print("生成: " .. file)

if send then
    local cmd = q(DIR .. "/wechat_send_file.sh") .. " " .. q(file)
    if to ~= "" then cmd = cmd .. " --to " .. q(to) end
    os.execute(cmd .. " >/dev/null 2>&1")
    print("已发送 -> " .. (to ~= "" and to or "文件传输助手"))
end
