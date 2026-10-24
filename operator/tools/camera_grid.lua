-- tools/camera_grid.lua — 四路摄像头抓帧 → 2×2 拼图 → 发微信
local DIR = (arg[0] or ""):match("^(.*)/") or "."

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local to, nosend, out = "", false, nil
local i = 1
while i <= #arg do
    if arg[i] == "--to" then to = arg[i + 1] or ""; i = i + 2
    elseif arg[i] == "--no-send" then nosend = true; i = i + 1
    elseif arg[i] == "--out" then out = arg[i + 1]; i = i + 2
    else i = i + 1 end
end

local tag = os.date("%Y%m%d_%H%M%S")
local tmp = "/tmp/myagent_camgrid_" .. tag
os.execute("mkdir -p " .. q(tmp))
local specs = {
    { name = "EZVIZ 客厅", args = "--ezviz keting", file = tmp .. "/1.jpg" },
    { name = "EZVIZ 门口", args = "--ezviz menkou", file = tmp .. "/2.jpg" },
    { name = "TP-Link", args = "--tplink", file = tmp .. "/3.jpg" },
    { name = "USB 摄像头", args = "--usb 0", file = tmp .. "/4.jpg" },
}
for _, s in ipairs(specs) do
    os.execute(q(DIR .. "/camera.sh") .. " " .. s.args .. " --out " .. q(s.file) .. " >/dev/null 2>&1")
    local f = io.open(s.file, "rb")
    local n = f and f:seek("end") or 0
    if f then f:close() end
    if not n or n == 0 then
        os.execute("convert -size 960x540 xc:'#202020' " .. q(s.file))
    end
end

out = out or ("/tmp/myagent_cameras_" .. tag .. ".jpg")
local font = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"
local cmd = "montage -background '#202020' -fill white -font " .. q(font) .. " -pointsize 30"
for _, s in ipairs(specs) do
    cmd = cmd .. " -label " .. q(s.name) .. " " .. q(s.file)
end
cmd = cmd .. " -tile 2x2 -geometry 960x540+10+10 " .. q(out)
if os.execute(cmd) ~= 0 then
    io.stderr:write("摄像头拼图失败\n")
    os.exit(1)
end
os.execute("rm -rf " .. q(tmp))
print(out)
if not nosend then
    local sc = q(DIR .. "/wechat_send_file.sh") .. " " .. q(out)
    if to ~= "" then sc = sc .. " --to " .. q(to) end
    os.execute(sc .. " >/dev/null 2>&1")
end
