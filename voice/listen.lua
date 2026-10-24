local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ffi = require("ffi")

ffi.cdef[[
int execv(const char *path, char *const argv[]);
]]

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local bin = DIR .. "/listen/listen"
if os.execute("test -x " .. q(bin) .. " >/dev/null 2>&1") ~= 0 then
    io.stderr:write("[voice] 未编译，正在编译...\n")
    if os.execute("make -C " .. q(DIR .. "/listen")) ~= 0 then
        io.stderr:write("[voice] 编译失败（需要 libasound2-dev）\n")
        os.exit(1)
    end
end

local args = { bin }
for i = 1, #arg do args[#args + 1] = arg[i] end
local argv = ffi.new("char *[?]", #args + 1)
for i, a in ipairs(args) do
    argv[i - 1] = ffi.cast("char *", a)
end
argv[#args] = nil
ffi.C.execv(bin, argv)
io.stderr:write("[voice] exec 失败: " .. bin .. "\n")
os.exit(1)
