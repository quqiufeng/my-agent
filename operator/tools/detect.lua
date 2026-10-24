local src, conf, to = "usb", "0.35", ""

local i = 1
while i <= #arg do
    if arg[i] == "--src" then src = arg[i + 1] or "usb"; i = i + 2
    elseif arg[i] == "--conf" then conf = arg[i + 1] or "0.35"; i = i + 2
    elseif arg[i] == "--to" then to = arg[i + 1] or ""; i = i + 2
    else i = i + 1 end
end

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local bin = "/opt/my-agent/agentkit/native_yolo/yolo_detect"
local model = "/opt/my-agent/agentkit/native_yolo/yolov8n.torchscript"

local f = io.open(bin, "rb")
if f then f:close() else os.execute("bash /opt/my-agent/agentkit/native_yolo/build.sh") end

local img, name
if src == "usb" then
    img, name = "/tmp/myagent_cam_usb.jpg", "usb"
elseif src == "keting" or src == "客厅" then
    img, name = "/tmp/myagent_cam_stream.jpg", "keting"
elseif src == "menkou" or src == "门口" then
    img, name = "/tmp/myagent_cam_door.jpg", "menkou"
else
    img, name = src, "src"
end

local input = io.open(img, "rb")
if not input then
    io.stderr:write("无抓帧: " .. img .. "（相机/app 未在跑？）\n")
    os.exit(1)
end
local size = input:seek("end")
input:close()
if not size or size == 0 then
    io.stderr:write("无抓帧: " .. img .. "（相机/app 未在跑？）\n")
    os.exit(1)
end

local out = "/tmp/det_" .. name .. ".jpg"
if os.execute(q(bin) .. " " .. q(model) .. " " .. q(img) .. " " .. q(out) .. " " .. q(conf)) ~= 0 then
    io.stderr:write("识别失败\n")
    os.exit(1)
end

if to ~= "" then
    local o = io.open(out, "rb")
    if o then
        o:close()
        os.execute(q("/opt/my-agent/operator/tools/wechat_send_file.sh") .. " " ..
            q(out) .. " --to " .. q(to) .. " >/dev/null 2>&1")
    end
end
print(out)
