local DIR = (arg[0] or ""):match("^(.*)/") or "."

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function size(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local n = f:seek("end") or 0
    f:close()
    return n
end

local BACKUP = os.getenv("IMAGE_BACKUP") or "/opt/static_comfyui/cpp/sd/backup.sh"
local W, H = 1080, 1920
local SECONDS = tonumber(os.getenv("IMGVID_SECONDS")) or 3

local prompts, imgdir, outimg = {}, nil, nil
local out, to, send, fg = nil, "", false, false
local preset = os.getenv("IMGVID_PRESET") or "xhs"
local iw = tonumber(os.getenv("IMGVID_W")) or 1024
local ih = tonumber(os.getenv("IMGVID_H")) or 1536
local n = nil

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--scenes" or a == "--prompt" then
        local v = arg[i + 1] or ""
        for p in (v .. "|"):gmatch("(.-)|") do
            if p ~= "" then prompts[#prompts + 1] = p end
        end
        i = i + 2
    elseif a == "--n" then n = tonumber(arg[i + 1]); i = i + 2
    elseif a == "--out" then out = arg[i + 1]; i = i + 2
    elseif a == "--outimg" then outimg = arg[i + 1]; i = i + 2
    elseif a == "--imgdir" then imgdir = arg[i + 1]; i = i + 2
    elseif a == "--img-preset" then preset = arg[i + 1] or "xhs"; i = i + 2
    elseif a == "--size" then
        local sz = arg[i + 1] or ""
        local w, h = sz:match("^(%d+)x(%d+)$")
        if w then iw, ih, preset = tonumber(w), tonumber(h), "none" end
        i = i + 2
    elseif a == "--seconds" then SECONDS = tonumber(arg[i + 1]) or SECONDS; i = i + 2
    elseif a == "--to" then to = arg[i + 1] or ""; send = true; i = i + 2
    elseif a == "--send" then send = true; i = i + 1
    elseif a == "--no-send" then send = false; i = i + 1
    elseif a == "--fg" then fg = true; i = i + 1
    elseif a == "--voice" or a == "--title" or a == "--end" or a == "--pinyin"
        or a == "--source" or a == "--text" then
        i = i + 2
    else
        if not a:match("^%-") then prompts[#prompts + 1] = a end
        i = i + 1
    end
end

if n and n > 0 then
    while #prompts > n do table.remove(prompts) end
end
if #prompts == 0 and not imgdir then
    io.stderr:write("用法: img_video.sh --scenes \"提示词1|提示词2|…\" [--out out.mp4] [--send] [--fg]\n" ..
        "       或: img_video.sh --imgdir <图片目录> [--out out.mp4] [--send] [--fg]\n")
    os.exit(2)
end

if not out or out == "" then
    out = (os.getenv("HOME") or "/root") .. "/image/图片视频_" ..
        os.date("%Y%m%d_%H%M%S") .. ".mp4"
end
local outdir = out:match("^(.*)/")
if outdir and outdir ~= "" then os.execute("mkdir -p " .. q(outdir)) end

local function fail(msg)
    io.stderr:write(msg .. "\n")
    if send then
        local cmd = q(DIR .. "/wechat_send.sh")
        if to ~= "" then cmd = cmd .. " --to " .. q(to) end
        os.execute(cmd .. " " .. q(msg) .. " >/dev/null 2>&1")
    end
    os.exit(1)
end

local function list_images(dir)
    local t = {}
    local p = io.popen("find " .. q(dir) ..
        " -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \\) | sort -V 2>/dev/null")
    if p then
        for line in p:lines() do if line ~= "" then t[#t + 1] = line end end
        p:close()
    end
    return t
end

local function run_pipeline()
    local work = "/tmp/imgvideo_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    local log = work .. ".log"
    os.execute("mkdir -p " .. q(work .. "/img"))
    local images = {}

    if imgdir then
        images = list_images(imgdir)
        if #images == 0 then fail("图片目录为空: " .. imgdir) end
        if n and n > 0 then
            while #images > n do table.remove(images) end
        end
    else
        local dest = outimg or (work .. "/img")
        os.execute("mkdir -p " .. q(dest))
        if os.execute("test -x " .. q(BACKUP) .. " >/dev/null 2>&1") ~= 0 then
            fail("backup.sh 不存在: " .. BACKUP)
        end
        for k, prompt in ipairs(prompts) do
            local img = string.format("%s/scene_%02d.png", dest, k - 1)
            local cmd
            if preset ~= "" and preset ~= "none" then
                cmd = q(BACKUP) .. " " .. q(prompt) .. " " .. q(img) .. " --preset " .. q(preset)
            else
                cmd = q(BACKUP) .. " " .. q(prompt) .. " " .. q(img) ..
                    " " .. tostring(iw) .. " " .. tostring(ih)
            end
            os.execute(cmd .. " >>" .. q(log) .. " 2>&1")
            local txt = ""
            local f = io.open(log, "r")
            if f then txt = f:read("*a") or ""; f:close() end
            txt = txt:gsub("\27%[[%d;]*m", "")
            local got
            for p in txt:gmatch("File:%s+(/[^%s]+%.png)") do got = p end
            if got and size(got) > 0 and got ~= img then
                os.execute("mv -f " .. q(got) .. " " .. q(img) .. " 2>/dev/null")
            end
            if size(img) == 0 then fail("出图失败（第 " .. k .. " 张）") end
            images[#images + 1] = img
        end
    end

    local list = work .. "/images.txt"
    local lf = assert(io.open(list, "w"))
    for _, img in ipairs(images) do
        lf:write("file '", img, "'\n")
        lf:write("duration ", SECONDS, "\n")
    end
    lf:write("file '", images[#images], "'\n")
    lf:close()

    os.execute("ffmpeg -y -f concat -safe 0 -i " .. q(list) ..
        " -vf " .. q("scale=" .. W .. ":" .. H ..
            ":force_original_aspect_ratio=increase,crop=" .. W .. ":" .. H ..
            ",format=yuv420p") ..
        " -r 25 -c:v libx264 -pix_fmt yuv420p -movflags +faststart " ..
        q(out) .. " >>" .. q(log) .. " 2>&1")

    if size(out) == 0 then fail("MP4 合成失败，日志: " .. log) end
    print("已生成: " .. out)
    if send then
        local cmd = q(DIR .. "/wechat_send_file.sh") .. " " .. q(out)
        if to ~= "" then cmd = cmd .. " --to " .. q(to) end
        os.execute(cmd .. " >/dev/null 2>&1")
        print("已发送 -> " .. (to ~= "" and to or "文件传输助手"))
    end
    os.execute("rm -rf " .. q(work))
end

if fg or os.getenv("IMGVIDEO_RUN") == "1" then
    run_pipeline()
else
    local id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    local log = "/tmp/imgvideo_" .. id .. ".out"
    local parts = { "setsid", "env", "IMGVIDEO_RUN=1", "luajit", q(DIR .. "/img_video.lua") }
    for _, a in ipairs(arg) do parts[#parts + 1] = q(a) end
    os.execute(table.concat(parts, " ") .. " </dev/null >" .. q(log) .. " 2>&1 &")
    print("已后台开始生成图片视频，完成后文件在 " .. out ..
        (send and "，并发送到微信" or "（未发微信）"))
end
