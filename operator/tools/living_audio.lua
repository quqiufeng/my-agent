local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local termexec = require("termexec")

local HOST = os.getenv("SMALLPC_HOST") or "quqiufeng@192.168.1.105"
local REMOTE_PID = "/tmp/living-audio.pid"
local REMOTE_LOG = "/tmp/living-audio.log"
local AOUT = os.getenv("SMALLPC_AOUT") or "alsa"
local ADEV = os.getenv("SMALLPC_ALSA_DEV") or "plughw:CARD=PCH,DEV=0"

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function usage()
    io.stderr:write("用法: tools/living_audio.sh say <文本> | play <本地文件|http(s) URL> | stop\n")
    os.exit(2)
end

local function remote(script, timeout)
    return termexec.run("ssh -o BatchMode=yes -o ConnectTimeout=5 " ..
        q(HOST) .. " " .. q(script), timeout)
end

local function stop_remote()
    remote("if [ -f '" .. REMOTE_PID .. "' ]; then kill $(cat '" .. REMOTE_PID ..
        "') 2>/dev/null || true; rm -f '" .. REMOTE_PID .. "'; fi", 20)
end

local function play_remote(src, label)
    stop_remote()
    local script = "nohup cvlc --intf dummy --play-and-exit --no-video --aout=" ..
        q(AOUT) .. " --alsa-audio-device=" .. q(ADEV) .. " " .. q(src) ..
        " >" .. q(REMOTE_LOG) .. " 2>&1 </dev/null & echo $! >" .. q(REMOTE_PID)
    local rc, out = remote(script, 30)
    if rc == nil or rc ~= 0 then
        io.stderr:write(out or "")
        io.stderr:write("启动小机箱 VLC 失败\n")
        os.exit(1)
    end
    print("客厅小音响播放: " .. label)
end

local function make_tts(text, out)
    local nodir = "/tmp/living-audio-nopath-" .. tostring(os.time())
    os.execute("mkdir -p " .. q(nodir))
    local f = assert(io.open(nodir .. "/pw-play", "w")); f:write("#!/bin/sh\nexit 0\n"); f:close()
    f = assert(io.open(nodir .. "/aplay", "w")); f:write("#!/bin/sh\nexit 0\n"); f:close()
    os.execute("chmod +x " .. q(nodir .. "/pw-play") .. " " .. q(nodir .. "/aplay"))
    local cmd = "PATH=" .. q(nodir .. ":" .. (os.getenv("PATH") or "/usr/bin:/bin")) ..
        " TTS_OUT=" .. q(out) .. " /opt/my-agent/voice/say.sh " .. q(text)
    local rc = os.execute(cmd)
    os.execute("rm -rf " .. q(nodir))
    local af = io.open(out, "rb")
    local sz = af and af:seek("end") or 0
    if af then af:close() end
    if rc ~= 0 or not sz or sz == 0 then
        io.stderr:write("本机 TTS 合成失败\n")
        os.exit(1)
    end
end

local cmd = arg[1] or ""

if cmd == "say" then
    local text = table.concat(arg, " ", 2)
    if text == "" then usage() end
    local wav = "/tmp/living-audio-" .. tostring(os.time()) .. ".wav"
    make_tts(text, wav)
    if termexec.run("scp -q -o BatchMode=yes " .. q(wav) ..
        " " .. q(HOST .. ":/tmp/living-audio-say.wav"), 40) ~= 0 then
        io.stderr:write("scp 到小机箱失败\n")
        os.exit(1)
    end
    play_remote("/tmp/living-audio-say.wav", text)
elseif cmd == "play" then
    local src = arg[2]
    if not src or src == "" then usage() end
    if src:match("^https?://") then
        play_remote(src, src)
    else
        local f = io.open(src, "rb")
        if not f then io.stderr:write("本地文件不存在: " .. src .. "\n"); os.exit(1) end
        f:close()
        local base = src:match("([^/]+)$") or "audio"
        local safe = base:gsub("[^A-Za-z0-9._-]", "_")
        local dst = "/tmp/living-audio-" .. safe
        if termexec.run("scp -q -o BatchMode=yes " .. q(src) ..
            " " .. q(HOST .. ":" .. dst), 40) ~= 0 then
            io.stderr:write("scp 到小机箱失败\n")
            os.exit(1)
        end
        play_remote(dst, base)
    end
elseif cmd == "stop" then
    stop_remote()
    print("已停止客厅小音响播放")
else
    usage()
end
