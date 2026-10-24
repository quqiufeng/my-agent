local DIR = (arg[0] or ""):match("^(.*)/") or "."

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
local urls = {}
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--to" then to = arg[i + 1] or ""; i = i + 2
    elseif a == "--save" then save = arg[i + 1]; i = i + 2
    elseif a == "--each" then each = true; i = i + 1
    elseif a == "--limit" then limit = tonumber(arg[i + 1]) or 0; i = i + 2
    else urls[#urls + 1] = a; i = i + 1 end
end

if os.execute("test -t 0") ~= 0 then
    for line in io.lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then urls[#urls + 1] = line end
    end
end

if #urls == 0 then
    io.stderr:write("用法: send_images.sh [--save 目录] [--to 会话] [--each] [--limit N] <图片URL...>\n")
    os.exit(2)
end

local d = "/tmp/myagent_imgs_" .. tostring(os.time())
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

if save then
    os.execute("mkdir -p " .. q(save) .. " 2>/dev/null")
    local prefix = os.getenv("SAVE_PREFIX") or ""
    for n, f in ipairs(files) do
        os.execute("cp -f " .. q(f) .. " " .. q(string.format("%s/%s%03d.jpg", save, prefix, n)) .. " 2>/dev/null")
    end
    os.execute("rm -rf " .. q(d))
    print("已保存 " .. #files .. " 张到 " .. save)
    os.exit(0)
end

print("下载 " .. #files .. " 张大图")

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
