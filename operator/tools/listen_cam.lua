local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local bg = require("bgjob")
require("dotenv").load()
local ezlib = require("ezviz")
local reg = require("device_registry")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local src, secs, save, play = "keting", 10, nil, true
local bgflag = false
for _, a in ipairs(arg) do
    if a == "keting" or a == "客厅" or a == "menkou" or a == "门口"
        or a == "usb" or a == "tplink" then
        src = a
    elseif a:match("^%d+$") then
        secs = tonumber(a) or secs
    end
end

local HELP = [[音频来源:
  keting/客厅   EZVIZ 客厅 HLS (/tmp/myagent_ezviz.url)
  menkou/门口   EZVIZ 门口 HLS (/tmp/myagent_door.url)
  tplink        TP-Link RTSP ( ~/.env 的 TPLINK_RTSP )
  usb           本机 USB 摄像头麦克风 (VOICE_MIC_DEV，默认 plughw:2,0)
  小机箱麦克风   未纳入统一入口；需要时 agent 可经 SSH/终端到小机箱处理

用法: listen_cam.sh [来源] [秒数] [--save 路径] [--play] [--bg]
文档: zspace.md 的「摄像头视频流」/「音频来源」]]
for _, a in ipairs(arg) do
    if a == "--help" or a == "-h" then print(HELP); os.exit(0) end
end
local i = 1
while i <= #arg do
    if arg[i] == "--save" then save = arg[i + 1]; play = false; i = i + 2
    elseif arg[i] == "--play" then play = true; i = i + 1
    elseif arg[i] == "--bg" then bgflag = true; i = i + 1
    else i = i + 1 end
end

if bgflag and os.getenv("BG_WORKER") ~= "1" then
    local j = bg.spawn_self(arg, "listen_cam")
    print("已后台录音 job=" .. j.id)
    print("查看进度: tools/jobs.sh tail " .. j.id)
    os.exit(0)
end

local input
if src == "tplink" then
    local t = reg.audio("tplink") or {}
    local url = os.getenv("TPLINK_RTSP") or ""
    if url == "" then
        local user = os.getenv("TPLINK_USER") or "admin"
        local pass = os.getenv("TPLINK_PASS") or ""
        local host = t.host or os.getenv("TPLINK_HOST") or "192.168.1.111"
        local port = t.port or 554
        local path = t.path or "/stream1"
        if pass ~= "" then url = "rtsp://" .. user .. ":" .. pass .. "@" .. host .. ":" .. tostring(port) .. path end
    end
    if url == "" then
        io.stderr:write("TPLINK_RTSP 未配置（~/.env）\n")
        os.exit(1)
    end
    input = "-rtsp_transport tcp -i " .. q(url)
elseif src == "usb" then
    local a = reg.audio("usb") or {}
    local dev = os.getenv("VOICE_MIC_DEV") or os.getenv("USB_MIC_DEV") or a.device or "plughw:2,0"
    input = "-f alsa -i " .. q(dev)
else
    local door = (src == "menkou" or src == "门口")
    local a = reg.audio(door and "menkou" or "keting") or {}
    local serial, urlfile = a.serial or ezlib.serial(door and "menkou" or "keting")
    if a.url_file then urlfile = a.url_file end
    local f = io.open(urlfile, "r")
    local url = f and (f:read("*l") or "") or ""
    if f then f:close() end
    url = url:gsub("^%s+", ""):gsub("%s+$", "")
    if url == "" then
        local nu, err = ezlib.refresh(serial, urlfile)
        if not nu then io.stderr:write("刷新 EZVIZ 地址失败: " .. tostring(err) .. "\n"); os.exit(1) end
        url = nu
    end
    input = "-i " .. q(url)
end

local out = save or ("/tmp/cam_audio_" .. os.date("%H%M%S") .. ".wav")
if os.execute("command -v ffmpeg >/dev/null 2>&1") ~= 0 then
    io.stderr:write("需要 ffmpeg\n")
    os.exit(3)
end

print("录音 " .. secs .. "s ← " .. src .. " ...")

if play and os.execute("command -v pw-play >/dev/null 2>&1") == 0 then
    local cmd = "timeout " .. tostring(secs + 15) ..
        " ffmpeg -hide_banner -loglevel error " .. input ..
        " -t " .. tostring(secs) .. " -vn -ac 1 -ar 16000 -f wav - 2>/dev/null" ..
        " | pw-play - 2>/dev/null"
    os.execute(cmd)
    print("（已外放 " .. secs .. "s）")
else
    local cmd = "timeout " .. tostring(secs + 15) ..
        " ffmpeg -hide_banner -loglevel error " .. input ..
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
