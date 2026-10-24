local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ffi = require("ffi")
ffi.cdef[[int setenv(const char *name, const char *value, int overwrite);]]

local function setenv(k, v)
    ffi.C.setenv(k, v, 1)
end

setenv("VOICE_PREFIX", "[英语口语]")
setenv("VOICE_ALWAYS", "1")
setenv("SENSEVOICE_LANG", os.getenv("SENSEVOICE_LANG_EN") or "auto")
setenv("KOKORO_SID", os.getenv("KOKORO_SID_EN") or "3")
setenv("VOICE_WAKE", "")

local flag = io.open("/tmp/myagent_english_mode", "w")
if flag then flag:close() end

print("[tutor] 英语口语陪练已开启：直接说英文即可，回复会用英文音色朗读；Ctrl+C 退出。")

local args = {}
for i = 1, #arg do args[#args + 1] = "'" .. arg[i]:gsub("'", "'\\''") .. "'" end
local rc = os.execute("luajit " .. DIR .. "/listen.lua " .. table.concat(args, " "))
os.remove("/tmp/myagent_english_mode")
os.exit(rc == 0 and 0 or 1)
