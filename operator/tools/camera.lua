local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local bg = require("bgjob")
require("dotenv").load()
local ezlib = require("ezviz")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function size(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local n = f:seek("end") or 0
    f:close()
    return n
end

local usb = os.getenv("CAM_USB_INDEX") or "0"
local bgflag = false
local tplink_flag = false
local rtsp = os.getenv("RTSP_URL") or ""
local ezviz, hls = "", ""
local out, live = nil, 0

local HELP = [[摄像头视频流:
  USB          /dev/video0 (V4L2，无账号/不过期)
  EZVIZ 客厅   /tmp/myagent_ezviz.url (HLS；过期自动刷新)
  EZVIZ 门口   /tmp/myagent_door.url (HLS；过期自动刷新)
  TP-Link      rtsp://admin:<TPLINK_PASS>@192.168.1.111:554/stream1 (RTSP)
              凭据: ~/.env 的 TPLINK_USER / TPLINK_PASS / TPLINK_RTSP

命令:
  camera.sh --usb 0
  camera.sh --ezviz keting|menkou
  camera.sh --hls <m3u8>
  camera.sh --rtsp <rtsp-url>
  camera.sh --tplink
  camera.sh ... --out <path> --live <秒> --bg

文档: zspace.md 的「摄像头视频流」；EZVIZ 地址过期会自动刷新。]]

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--help" or a == "-h" or a == "--list" then print(HELP); os.exit(0)
    elseif a == "--usb" then usb = arg[i + 1] or "0"; i = i + 2
    elseif a == "--rtsp" then rtsp = arg[i + 1] or ""; i = i + 2
    elseif a == "--ezviz" then ezviz = arg[i + 1] or "keting"; i = i + 2
    elseif a == "--hls" then hls = arg[i + 1] or ""; i = i + 2
    elseif a == "--tplink" then
        tplink_flag = true
        rtsp = os.getenv("TPLINK_RTSP") or ""
        if rtsp == "" then
            local user = os.getenv("TPLINK_USER") or "admin"
            local pass = os.getenv("TPLINK_PASS") or ""
            local host = os.getenv("TPLINK_HOST") or "192.168.1.111"
            if pass ~= "" then
                rtsp = "rtsp://" .. user .. ":" .. pass .. "@" .. host .. ":554/stream1"
            end
        end
        i = i + 1
    elseif a == "--out" then out = arg[i + 1]; i = i + 2
    elseif a == "--live" then live = tonumber(arg[i + 1]) or 5; i = i + 2
    elseif a == "--bg" then bgflag = true; i = i + 1
    else i = i + 1 end
end

if bgflag and os.getenv("BG_WORKER") ~= "1" then
    local j = bg.spawn_self(arg, "camera")
    print("已后台采集摄像头 job=" .. j.id)
    print("查看进度: tools/jobs.sh tail " .. j.id)
    os.exit(0)
end

if tplink_flag and rtsp == "" then
    io.stderr:write("TPLINK_RTSP 未配置（~/.env）\n")
    os.exit(3)
end

if os.execute("command -v ffmpeg >/dev/null 2>&1") ~= 0 then
    io.stderr:write("需要 ffmpeg\n")
    os.exit(3)
end

local live_jpg, src, ez_serial, ez_file
if ezviz ~= "" then
    local door = (ezviz == "menkou" or ezviz == "门口")
    local kind = door and "menkou" or "keting"
    ez_serial, ez_file = ezlib.serial(kind)
    local f = io.open(ez_file, "r")
    local u = f and (f:read("*l") or "") or ""
    if f then f:close() end
    u = u:gsub("^%s+", ""):gsub("%s+$", "")
    if u == "" then
        local nu, err = ezlib.refresh(ez_serial, ez_file)
        if not nu then io.stderr:write("刷新 EZVIZ 地址失败: " .. tostring(err) .. "\n"); os.exit(1) end
        u = nu
        io.stderr:write("已刷新 EZVIZ 地址: " .. ez_file .. "\n")
    end
    live_jpg = door and "/tmp/myagent_cam_door.jpg" or "/tmp/myagent_cam_stream.jpg"
    src = "-i " .. q(u)
elseif hls ~= "" then
    live_jpg = "/tmp/myagent_cam_hls.jpg"
    src = "-i " .. q(hls)
elseif rtsp ~= "" then
    live_jpg = "/tmp/myagent_cam_rtsp.jpg"
    if rtsp:match("^https?://") then
        src = "-i " .. q(rtsp)
    else
        src = "-rtsp_transport tcp -i " .. q(rtsp)
    end
else
    live_jpg = "/tmp/myagent_cam_usb.jpg"
    src = "-f v4l2 -i " .. q("/dev/video" .. usb)
end
if not out then out = live_jpg end

if live == 0 and size(live_jpg) > 0 then
    local p = io.popen("stat -c %Y " .. q(live_jpg) .. " 2>/dev/null")
    local mt = tonumber(p and p:read("*l") or "") or 0
    if p then p:close() end
    if os.time() - mt <= 8 then print(live_jpg); os.exit(0) end
end

if live > 0 then
    out = out:gsub("%.[^%.]*$", "") .. ".mp4"
end

local function run_capture()
    if live > 0 then
        os.execute("ffmpeg -loglevel error -y " .. src .. " -t " .. tostring(live) ..
            " -c:v libx264 -preset veryfast " .. q(out))
    else
        os.execute("ffmpeg -loglevel error -y " .. src .. " -frames:v 1 " ..
            q(out) .. " 2>/tmp/myagent_cam.err")
    end
end

run_capture()
if size(out) == 0 and ez_serial then
    local nu = ezlib.refresh(ez_serial, ez_file)
    if nu then
        io.stderr:write("地址失效，已自动刷新: " .. ez_file .. "\n")
        src = "-i " .. q(nu)
        run_capture()
    end
end

if size(out) > 0 then print(out); os.exit(0) end
if size(live_jpg) > 0 then print(live_jpg); os.exit(0) end

local p = io.popen("tail -1 /tmp/myagent_cam.err 2>/dev/null")
local err = p and p:read("*l") or ""
if p then p:close() end
io.stderr:write("抓取失败: " .. (err ~= "" and err or "未知错误") .. "\n")
os.exit(1)
