local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local bg = require("bgjob")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local src, secs, save, play = "keting", 10, nil, true
local bgflag = false
for _, a in ipairs(arg) do
    if a == "keting" or a == "客厅" or a == "menkou" or a == "门口" or a == "usb" then
        src = a
    elseif a:match("^%d+$") then
        secs = tonumber(a) or secs
    end
end
local i = 1
while i <= #arg do
    if arg[i] == "--save" then save = arg[i + 1]; play = false; i = i + 2
    elseif arg[i] == "--play" then play = true; i = i + 1
    elseif arg[i] == "--bg" then bgflag = true; i = i + 1
    else i = i + 1 end
end

local urlfile
if src == "menkou" or src == "门口" then
    urlfile = "/tmp/myagent_door.url"
else
    urlfile = "/tmp/myagent_ezviz.url"
end

if bgflag and os.getenv("BG_WORKER") ~= "1" then
    local j = bg.spawn_self(arg, "listen_cam")
    print("已后台录音 job=" .. j.id)
    print("查看进度: tools/jobs.sh tail " .. j.id)
    os.exit(0)
end

local f = io.open(urlfile, "r")
local url = f and (f:read("*l") or "") or ""
if f then f:close() end
url = url:gsub("^%s+", ""):gsub("%s+$", "")
if url == "" then
    io.stderr:write("无地址(" .. urlfile .. ")；先 tools/ezviz_url.sh 生成\n")
    os.exit(1)
end

local out = save or ("/tmp/cam_audio_" .. os.date("%H%M%S") .. ".wav")
if os.execute("command -v ffmpeg >/dev/null 2>&1") ~= 0 then
    io.stderr:write("需要 ffmpeg\n")
    os.exit(3)
end

print("录音 " .. secs .. "s ← " .. src .. " ...")

if play and os.execute("command -v pw-play >/dev/null 2>&1") == 0 then
    local cmd = "timeout " .. tostring(secs + 15) ..
        " ffmpeg -hide_banner -loglevel error -i " .. q(url) ..
        " -t " .. tostring(secs) .. " -vn -ac 1 -ar 16000 -f wav - 2>/dev/null" ..
        " | pw-play - 2>/dev/null"
    os.execute(cmd)
    print("（已外放 " .. secs .. "s）")
else
    local cmd = "timeout " .. tostring(secs + 15) ..
        " ffmpeg -hide_banner -loglevel error -i " .. q(url) ..
        " -t " .. tostring(secs) .. " -vn -ac 1 -ar 16000 -y " .. q(out) .. " 2>/dev/null"
    os.execute(cmd)
    local of = io.open(out, "rb")
    if of then
        local n = of:seek("end") or 0
        of:close()
        if n > 0 then print(out); os.exit(0) end
    end
    os.exit(1)
end
