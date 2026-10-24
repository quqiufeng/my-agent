local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local bg = require("bgjob")

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
local rtsp = os.getenv("RTSP_URL") or ""
local out, live = nil, 0

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--usb" then usb = arg[i + 1] or "0"; i = i + 2
    elseif a == "--rtsp" then rtsp = arg[i + 1] or ""; i = i + 2
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

if os.execute("command -v ffmpeg >/dev/null 2>&1") ~= 0 then
    io.stderr:write("需要 ffmpeg\n")
    os.exit(3)
end

local live_jpg, src
if rtsp ~= "" then
    live_jpg = "/tmp/myagent_cam_rtsp.jpg"
    src = "-rtsp_transport tcp -i " .. q(rtsp)
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
    os.execute("ffmpeg -loglevel error -y " .. src .. " -t " .. tostring(live) ..
        " -c:v libx264 -preset veryfast " .. q(out))
else
    os.execute("ffmpeg -loglevel error -y " .. src .. " -frames:v 1 " ..
        q(out) .. " 2>/tmp/myagent_cam.err")
end

if size(out) > 0 then print(out); os.exit(0) end
if size(live_jpg) > 0 then print(live_jpg); os.exit(0) end

local p = io.popen("tail -1 /tmp/myagent_cam.err 2>/dev/null")
local err = p and p:read("*l") or ""
if p then p:close() end
io.stderr:write("抓取失败: " .. (err ~= "" and err or "未知错误") .. "\n")
os.exit(1)
