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

local function tidy(u)
    return (u:gsub("/(orj360|orj480|thumb150|thumb180|thumbnail|mw690|small|wap360|bmiddle)/", "/large/"))
end

local to, save, each, limit = "", nil, false, 0
local fg, input_file, dir_shot = false, nil, false
local urls = {}
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--to" then to = arg[i + 1] or ""; i = i + 2
    elseif a == "--save" then save = arg[i + 1]; i = i + 2
    elseif a == "--each" then each = true; i = i + 1
    elseif a == "--limit" then limit = tonumber(arg[i + 1]) or 0; i = i + 2
    elseif a == "--input-file" then input_file = arg[i + 1]; i = i + 2
    elseif a == "--fg" then fg = true; i = i + 1
    elseif a == "--dir-shot" then dir_shot = true; i = i + 1
    else urls[#urls + 1] = a; i = i + 1 end
end

local from_stdin = false
if input_file then
    local f = io.open(input_file, "r")
    if f then
        for line in f:lines() do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then urls[#urls + 1] = line end
        end
        f:close()
    end
    os.remove(input_file)
elseif os.execute("test -t 0") ~= 0 then
    from_stdin = true
    for line in io.lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then urls[#urls + 1] = line end
    end
end

do
    local seen, uniq = {}, {}
    for _, u in ipairs(urls) do
        if not seen[u] then seen[u] = true; uniq[#uniq + 1] = u end
    end
    urls = uniq
end

if #urls == 0 then
    io.stderr:write("用法: send_images.sh [--save 目录] [--to 会话] [--each] [--dir-shot] [--limit N] <图片URL...>\n")
    os.exit(2)
end
if dir_shot and not save then
    io.stderr:write("--dir-shot 需要 --save 目录\n")
    os.exit(2)
end

local home = os.getenv("HOME") or "/tmp"
local cache = home .. "/.cache/myagent"
os.execute("mkdir -p " .. q(cache))

if not fg and os.getenv("BG_WORKER") ~= "1" then
    local args = {}
    for _, a in ipairs(arg) do args[#args + 1] = a end
    if from_stdin then
        local tmp = cache .. "/send_images_input_" .. tostring(os.time()) .. ".txt"
        local f = assert(io.open(tmp, "w"))
        for _, u in ipairs(urls) do f:write(u, "\n") end
        f:close()
        args[#args + 1] = "--input-file"
        args[#args + 1] = tmp
    end
    local j = bg.spawn_self(args, "send_images")
    print("已后台下载图片 job=" .. j.id)
    print("查看进度: tools/jobs.sh tail " .. j.id)
    os.exit(0)
end

local d = cache .. "/imgs_" .. tostring(os.time())
os.execute("mkdir -p " .. q(d))
local uf = assert(io.open(d .. "/urls", "w"))
local count = 0
for _, u in ipairs(urls) do
    count = count + 1
    if limit > 0 and count > limit then break end
    uf:write(string.format("%05d %s\n", count, tidy(u)))
end
uf:close()

local dl = [[
out="$D/$1.jpg"; u="$2"
curl -sL --max-time 40 -A "Mozilla/5.0" -H "Referer: https://weibo.com/" -o "$out" "$u" 2>/dev/null
if [ ! -s "$out" ]; then
  for s in mw690 large orj360 thumb150; do
    v="$(printf "%s" "$u" | sed -E "s#/(large|mw690|orj360|thumb150|thumb180|orj480|thumbnail|small|wap360|bmiddle)/#/$s/#")"
    curl -sL --max-time 40 -A "Mozilla/5.0" -H "Referer: https://weibo.com/" -o "$out" "$v" 2>/dev/null
    [ -s "$out" ] && break
  done
fi
]]
os.execute("D=" .. q(d) .. " xargs -a " .. q(d .. "/urls") ..
    " -P 8 -n 2 sh -c " .. q(dl) .. " _")

local files = {}
local p = io.popen("ls " .. q(d) .. "/[0-9]*.jpg 2>/dev/null | sort")
if p then
    for line in p:lines() do
        if size(line) > 0 and os.execute("identify " .. q(line) .. " >/dev/null 2>&1") == 0 then
            files[#files + 1] = line
        else
            os.remove(line)
        end
    end
    p:close()
end

if #files == 0 then
    io.stderr:write("没下到图片（URL 可能失效）\n")
    os.exit(1)
end

print("下载 " .. #files .. " 张大图")

local function send_dir_shot(dir, target)
    if target == "" then return false end
    local ok, Xdo = pcall(require, "xdo")
    if not ok or not Xdo.new then return false end
    local dpy = Xdo.new()
    if not dpy then return false end
    local before = {}
    for _, w in ipairs(dpy:windows()) do before[tostring(w.id)] = true end
    local base = dir:match("([^/]+)/*$") or dir
    local pidfile = cache .. "/pcmanfm_dirshot.pid"
    os.execute("pcmanfm-qt -n " .. q(dir) .. " >/dev/null 2>&1 & echo $! > " .. q(pidfile))
    local wid
    for _ = 1, 50 do
        os.execute("sleep 0.15")
        for _, w in ipairs(dpy:windows()) do
            local id, name = tostring(w.id), (w.name or "")
            if not before[id] and name ~= "" and name ~= "pcmanfm-desktop0" and name:find(base, 1, true) then
                wid = w.id; break
            end
        end
        if wid then break end
    end
    if not wid then
        local pf = io.open(pidfile, "r")
        local pid = pf and (pf:read("*a") or ""):gsub("%s+$", ""); if pf then pf:close() end
        if pid and pid ~= "" then os.execute("kill " .. q(pid) .. " 2>/dev/null") end
        os.remove(pidfile)
        dpy:close()
        return false
    end
    os.remove(pidfile)
    local id = tostring(wid)
    os.execute("wmctrl -i -r " .. id .. " -b add,maximized_vert,maximized_horz 2>/dev/null")
    dpy:activate(wid); dpy:raise(wid)
    os.execute("sleep 2")
    local shot = cache .. "/dirshot_" .. tostring(os.time()) .. ".png"
    os.execute("import -window root " .. q(shot) .. " 2>/dev/null")
    local rc = size(shot) > 1000
    if rc then
        local cmd = q(DIR .. "/wechat_send_file.sh") .. " " .. q(shot)
        cmd = cmd .. " --to " .. q(target)
        rc = os.execute(cmd .. " >/dev/null 2>&1") == 0
    end
    os.remove(shot)
    os.execute("wmctrl -i -c " .. id .. " 2>/dev/null")
    os.execute("sleep 0.5")
    dpy:close()
    return rc
end

if save then
    os.execute("mkdir -p " .. q(save) .. " 2>/dev/null")
    local prefix = os.getenv("SAVE_PREFIX") or ""
    for n, f in ipairs(files) do
        os.execute("cp -f " .. q(f) .. " " .. q(string.format("%s/%s%03d.jpg", save, prefix, n)) .. " 2>/dev/null")
    end
    print("已保存 " .. #files .. " 张到 " .. save)
    if to == "" then
        os.execute("rm -rf " .. q(d))
        os.exit(0)
    end
    if dir_shot then
        local ok = send_dir_shot(save, to)
        os.execute("rm -rf " .. q(d))
        print(ok and ("已发文件管理器截图(" .. #files .. "张) -> " .. to) or "发送文件管理器截图失败")
        os.exit(ok and 0 or 1)
    end
end

local function send(path)
    local cmd = q(DIR .. "/wechat_send_file.sh") .. " " .. q(path)
    if to ~= "" then cmd = cmd .. " --to " .. q(to) end
    os.execute(cmd .. " >/dev/null 2>&1")
end

if each then
    for _, f in ipairs(files) do send(f) end
    print("已发 " .. #files .. " 张 -> " .. (to ~= "" and to or "文件传输助手"))
else
    local sheet = d .. "/sheet.jpg"
    if #files == 1 then
        os.execute("cp " .. q(files[1]) .. " " .. q(sheet))
    else
        local cmd = "montage"
        for _, f in ipairs(files) do cmd = cmd .. " " .. q(f) end
        cmd = cmd .. " -tile 3x -geometry 520x520+6+6 -background '#ffffff' " .. q(sheet) .. " 2>/dev/null"
        if os.execute(cmd) ~= 0 then os.execute("cp " .. q(files[1]) .. " " .. q(sheet)) end
    end
    send(sheet)
    print("已发拼图(" .. #files .. "张) -> " .. (to ~= "" and to or "文件传输助手"))
end
os.execute("rm -rf " .. q(d))
