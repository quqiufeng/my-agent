local DIR = (arg[0] or ""):match("^(.*)/") or "."
local src, conf, to = "usb", "0.35", ""
local grid = false

local i = 1
while i <= #arg do
    if arg[i] == "--src" then src = arg[i + 1] or "usb"; i = i + 2
    elseif arg[i] == "--conf" then conf = arg[i + 1] or "0.35"; i = i + 2
    elseif arg[i] == "--to" then to = arg[i + 1] or ""; i = i + 2
    elseif arg[i] == "--grid" then grid = true; i = i + 1
    else i = i + 1 end
end

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local bin = "/opt/my-agent/agentkit/native_yolo/yolo_detect"
local model = "/opt/my-agent/agentkit/native_yolo/yolov8n.torchscript"

local f = io.open(bin, "rb")
if f then f:close() else os.execute("bash /opt/my-agent/agentkit/native_yolo/build.sh") end

local function img_size(path)
    local p = io.popen("identify -format '%w %h' " .. q(path) .. " 2>/dev/null")
    local o = p and (p:read("*a") or "") or ""; if p then p:close() end
    local w, h = o:match("(%d+)%s+(%d+)")
    return tonumber(w) or 0, tonumber(h) or 0
end

local function yolo(img, out)
    local p = io.popen(q(bin) .. " " .. q(model) .. " " .. q(img) .. " " .. q(out) .. " " .. q(conf) .. " 2>/dev/null")
    local boxes = {}
    if p then
        for line in p:lines() do
            local cls, x1, y1, x2, y2 = line:match("^(%S+)%s+[%d%.]+%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
            if cls == "person" then
                boxes[#boxes + 1] = { tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2) }
            end
        end
        p:close()
    end
    return boxes
end

local function iou(a, b)
    local ix = math.max(0, math.min(a[3], b[3]) - math.max(a[1], b[1]))
    local iy = math.max(0, math.min(a[4], b[4]) - math.max(a[2], b[2]))
    local inter = ix * iy
    local ua = (a[3]-a[1])*(a[4]-a[2]) + (b[3]-b[1])*(b[4]-b[2]) - inter
    return ua > 0 and inter / ua or 0
end

local function run_grid()
    local tag = os.date("%Y%m%d_%H%M%S")
    local dir = "/tmp/myagent_det_grid_" .. tag
    os.execute("mkdir -p " .. q(dir))
    local specs = {
        { name = "EZVIZ 客厅", args = "--ezviz keting" },
        { name = "EZVIZ 门口", args = "--ezviz menkou" },
        { name = "TP-Link", args = "--tplink" },
        { name = "USB", args = "--usb 0" },
    }
    local counts, ann = {}, {}
    local total = 0
    for i, s in ipairs(specs) do
        local src = dir .. "/" .. i .. ".jpg"
        local full = dir .. "/" .. i .. "_full.jpg"
        os.execute(q(DIR .. "/camera.sh") .. " " .. s.args .. " --out " .. q(src) .. " >/dev/null 2>&1")
        local f = io.open(src, "rb")
        local n = f and f:seek("end") or 0
        if f then f:close() end
        local boxes = {}
        local base = src
        if n and n > 0 then
            boxes = yolo(src, full)
            base = full
            -- 全身框漏检时，用 45% 四宫格再找一次（远景/躺卧的人）
            if #boxes == 0 then
                local W, H = img_size(src)
                local tw, th = math.floor(W * 0.45), math.floor(H * 0.45)
                local xs, ys = { 0, W - tw }, { 0, H - th }
                for yi = 1, 2 do
                    for xi = 1, 2 do
                        local tile = dir .. "/" .. i .. "_t" .. yi .. xi .. ".jpg"
                        local tdet = dir .. "/" .. i .. "_t" .. yi .. xi .. "_det.jpg"
                        os.execute("convert " .. q(src) .. " -crop " .. tw .. "x" .. th .. "+" .. xs[xi] .. "+" .. ys[yi] .. " +repage " .. q(tile) .. " 2>/dev/null")
                        for _, b in ipairs(yolo(tile, tdet)) do
                            local nb = { b[1] + xs[xi], b[2] + ys[yi], b[3] + xs[xi], b[4] + ys[yi] }
                            local dup = false
                            for _, old in ipairs(boxes) do
                                if iou(nb, old) > 0.35 then dup = true; break end
                            end
                            if not dup then boxes[#boxes + 1] = nb end
                        end
                    end
                end
            end
        end
        if #boxes > 0 and base == src then
            -- 没有现成标注图，就在原图上画绿框
            local draw = {}
            for _, b in ipairs(boxes) do
                draw[#draw + 1] = string.format("rectangle %d,%d %d,%d", b[1], b[2], b[3], b[4])
            end
            local outb = dir .. "/" .. i .. "_marked.jpg"
            os.execute("convert " .. q(src) .. " -stroke '#00ff00' -strokewidth 6 -fill none -draw " .. q(table.concat(draw, " ")) .. " " .. q(outb) .. " 2>/dev/null")
            base = outb
        elseif #boxes > 0 and base ~= src then
            -- full 图只画了红框；补画拼图找回的绿框
            local tileboxes = {}
            -- 简单起见：所有 person 框都补画，重叠不致命
            local draw = {}
            for _, b in ipairs(boxes) do draw[#draw + 1] = string.format("rectangle %d,%d %d,%d", b[1], b[2], b[3], b[4]) end
            if #draw > 0 then
                local outb = dir .. "/" .. i .. "_marked.jpg"
                os.execute("convert " .. q(base) .. " -stroke '#00ff00' -strokewidth 6 -fill none -draw " .. q(table.concat(draw, " ")) .. " " .. q(outb) .. " 2>/dev/null")
                base = outb
            end
        end
        local df = io.open(base, "rb")
        if not df or (df:seek("end") or 0) == 0 then
            if df then df:close() end
            base = dir .. "/" .. i .. "_blank.jpg"
            os.execute("convert -size 960x540 xc:'#202020' " .. q(base))
        elseif df then df:close() end
        counts[i], ann[i] = #boxes, base
        total = total + #boxes
    end
    local font = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"
    local cmd = "montage -background '#202020' -fill white -font " .. q(font) .. " -pointsize 30"
    for i, s in ipairs(specs) do cmd = cmd .. " -label " .. q(s.name) .. " " .. q(ann[i]) end
    cmd = cmd .. " -tile 2x2 -geometry 960x540+10+10 " .. q("/tmp/det_grid.jpg")
    os.execute(cmd .. " >/dev/null 2>&1")
    os.execute("rm -rf " .. q(dir))
    local lines = {}
    for i, s in ipairs(specs) do lines[#lines + 1] = s.name .. ": " .. counts[i] .. " 人" end
    local summary = total == 0 and "四路均未检测到人" or ("检测到人 → " .. table.concat(lines, "；"))
    print(summary)
    print("图片: /tmp/det_grid.jpg")
    if to ~= "" then
        os.execute(q(DIR .. "/wechat_send_file.sh") .. " /tmp/det_grid.jpg --to " .. q(to) .. " >/dev/null 2>&1")
        os.execute(q(DIR .. "/wechat_send.sh") .. " --to " .. q(to) .. " " .. q(summary) .. " >/dev/null 2>&1")
    end
end
if grid then run_grid(); os.exit(0) end

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
