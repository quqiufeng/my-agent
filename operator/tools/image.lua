local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local bg = require("bgjob")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local to, prompt, w, h, force, preset = "", "", nil, nil, false, ""
local fg = false
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--to" then to = arg[i + 1] or ""; i = i + 2
    elseif a == "--force" then force = true; i = i + 1
    elseif a == "--fg" then fg = true; i = i + 1
    elseif a == "小红书" or a == "小红薯" or a == "xhs" or a == "xiaohongshu" or a == "竖版" then
        preset = "xhs"; i = i + 1
    elseif a == "朋友圈" or a == "pyq" or a == "moments" or a == "方图" or a == "方版" then
        preset = "pyq"; i = i + 1
    elseif a == "横版" or a == "横图" or a == "大屏" or a == "默认" then
        preset = ""; i = i + 1
    elseif a:match("^%d+$") then
        if not w then w = tonumber(a) else h = tonumber(a) end
        i = i + 1
    else
        if prompt == "" then prompt = a end
        i = i + 1
    end
end

if preset == "xhs" then w, h = 1920, 2560
elseif preset == "pyq" then w, h = 2048, 2048
else w, h = w or 2560, h or 1440 end

if prompt == "" then
    io.stderr:write("用法: image.sh [--to 会话] [--force] [小红书|小红薯|朋友圈] \"提示词\" [宽] [高]\n")
    os.exit(2)
end

local backup = os.getenv("IMAGE_BACKUP") or "/opt/static_comfyui/cpp/sd/backup.sh"
if not exists(backup) then
    io.stderr:write("backup.sh 不存在: " .. backup .. "\n")
    os.exit(1)
end

if os.execute("command -v nvidia-smi >/dev/null 2>&1") == 0 then
    local p = io.popen("nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' '")
    local free = p and tonumber(p:read("*l") or "") or nil
    if p then p:close() end
    if free and free < 8000 and not force then
        io.stderr:write("GPU 显存不足（空闲 " .. free ..
            " MiB），出图可能 OOM/极慢。稍后再试或加 --force。\n")
        os.exit(3)
    end
end

if not fg and os.getenv("BG_WORKER") ~= "1" then
    local j = bg.spawn_self(arg, "image")
    print("已后台出图 job=" .. j.id)
    print("查看进度: tools/jobs.sh tail " .. j.id)
    os.exit(0)
end

local stamp = os.date("%Y%m%d_%H%M%S")
local home = os.getenv("HOME") or "/root"
local outbase = home .. "/gen_" .. stamp .. ".png"
local log = "/tmp/myagent_img_" .. stamp .. ".log"
local size_name = preset == "xhs" and "小红书" or (preset == "pyq" and "朋友圈" or "横版")
print("开始出图（" .. size_name .. " " .. w .. "x" .. h ..
    "），请稍候（约 3~5 分钟）...")

local cmd
if preset ~= "" then
    cmd = q(backup) .. " " .. q(prompt) .. " " .. q(outbase) .. " --preset " .. q(preset)
else
    cmd = q(backup) .. " " .. q(prompt) .. " " .. q(outbase) .. " " .. tostring(w) .. " " .. tostring(h)
end
os.execute(cmd .. " >" .. q(log) .. " 2>&1")

local f = io.open(log, "r")
local text = f and (f:read("*a") or "") or ""
if f then f:close() end
text = text:gsub("\27%[[%d;]*m", "")

local img = nil
for p in text:gmatch("File:%s+(/[^%s]+%.png)") do img = p end
if not img or not exists(img) then
    local paths = {}
    for p in text:gmatch("(/[^%s]+%.png)") do paths[#paths + 1] = p end
    for n = #paths, 1, -1 do
        if exists(paths[n]) then img = paths[n]; break end
    end
end
if not img then
    print("出图失败，日志尾部：")
    local lines = {}
    for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
    for n = math.max(1, #lines - 19), #lines do print(lines[n]) end
    os.exit(1)
end

print("出图完成: " .. img)
local sc = q(DIR .. "/wechat_send_file.sh") .. " " .. q(img)
if to ~= "" then sc = sc .. " --to " .. q(to) end
os.execute(sc)
local base = img:match("([^/]+)$") or img
if to ~= "" then
    print("已发送到微信「" .. to .. "」: " .. base)
else
    print("已发送到微信文件传输助手: " .. base)
end
