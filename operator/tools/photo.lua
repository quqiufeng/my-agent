local DIR = (arg[0] or ""):match("^(.*)/") or "."

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function file_size(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local n = f:seek("end") or 0
    f:close()
    return n
end

local dev = os.getenv("CAM_DEV") or "/dev/video0"
local size = os.getenv("PHOTO_SIZE") or "1920x1080"
local to, out, burst, nosend = "", nil, 1, false

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--to" then to = arg[i + 1] or ""; i = i + 2
    elseif a == "--size" then size = arg[i + 1] or size; i = i + 2
    elseif a == "--device" then dev = arg[i + 1] or dev; i = i + 2
    elseif a == "--save" then out = arg[i + 1]; i = i + 2
    elseif a == "--burst" then burst = tonumber(arg[i + 1]) or 1; i = i + 2
    elseif a == "--no-send" then nosend = true; i = i + 1
    else i = i + 1 end
end

if os.execute("test -e " .. q(dev)) ~= 0 then
    io.stderr:write("摄像头不存在: " .. dev .. "\n")
    os.exit(1)
end
if burst < 1 then burst = 1 end
burst = math.floor(burst)

out = out or ("/tmp/myagent_photo_" .. os.date("%Y%m%d_%H%M%S") .. ".jpg")

local function capture(sz, path)
    local cmd = "ffmpeg -hide_banner -loglevel error -f v4l2 -input_format mjpeg" ..
        " -video_size " .. q(sz) .. " -i " .. q(dev) ..
        " -frames:v 1 -y " .. q(path) .. " 2>/dev/null"
    if os.execute(cmd) ~= 0 then return false end
    return file_size(path) > 0
end

local files = {}
for n = 1, burst do
    local path
    if burst == 1 then
        path = out
    else
        path = "/tmp/myagent_photo_" .. os.date("%Y%m%d_%H%M%S") .. "_" .. n .. ".jpg"
    end

    local ok = false
    for _, sz in ipairs({ size, "1280x720", "640x480" }) do
        if capture(sz, path) then ok = true; break end
    end
    if not ok then
        io.stderr:write("拍照失败（设备忙或参数不支持）: " .. dev .. "\n")
        if #files == 0 then os.exit(1) end
        break
    end
    files[#files + 1] = path

    local p = io.popen("identify -format '%wx%h' " .. q(path) .. " 2>/dev/null")
    local dim = p and p:read("*a") or ""
    if p then p:close() end
    print("已拍照: " .. path .. " (" .. dim .. ")")
    if n < burst then os.execute("sleep 1") end
end

if nosend then
    for _, path in ipairs(files) do print(path) end
    os.exit(0)
end

for _, path in ipairs(files) do
    local cmd = q(DIR .. "/wechat_send_file.sh") .. " " .. q(path)
    if to ~= "" then cmd = cmd .. " --to " .. q(to) end
    os.execute(cmd .. " >/dev/null 2>&1")
end
print("已发送 " .. #files .. " 张 -> " .. (to ~= "" and to or "文件传输助手"))
