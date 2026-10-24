local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path

local cjson = require("cjson")

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

local UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36"

local function extract_sec(u)
    local sec = u:match("/user/([^/?]+)")
    if sec then return sec end
    local p = io.popen("curl -sIL --max-time 20 -A " .. q(UA) ..
        " -o /dev/null -w '%{url_effective}' " .. q(u) .. " 2>/dev/null")
    local final = p and p:read("*a") or ""
    if p then p:close() end
    return final:match("/user/([^/?]+)")
end

local cmd = "list"
local start = 1
if arg[1] == "list" or arg[1] == "get" then cmd = arg[1]; start = 2 end

local n, minlike, sec = 18, 30, ""
local i = start
while i <= #arg do
    local a = arg[i]
    if a == "--min-like" then minlike = tonumber(arg[i + 1]) or 30; i = i + 2
    elseif a == "--uid" then sec = arg[i + 1] or ""; i = i + 2
    elseif a == "--url" then sec = extract_sec(arg[i + 1] or "") or ""; i = i + 2
    elseif a:match("^https?://") then sec = extract_sec(a) or ""; i = i + 1
    elseif a:match("^%d+$") then n = tonumber(a) or n; i = i + 1
    else i = i + 1 end
end

local rc = os.execute("node " .. q(DIR .. "/douyin_fetch.js") .. " " ..
    tostring(n) .. " " .. q(sec))
if rc ~= 0 then
    io.stderr:write("抖音取数失败：确认 Chrome 已登录抖音、且开着远程调试(9222)。\n")
    os.exit(1)
end

local jf = io.open("/tmp/douyin_list.json", "r")
if not jf then io.stderr:write("未取到作品列表\n"); os.exit(1) end
local raw = jf:read("*a") or ""
jf:close()
local ok, list = pcall(cjson.decode, raw)
if not ok or type(list) ~= "table" then io.stderr:write("作品列表解析失败\n"); os.exit(1) end

local home = os.getenv("HOME") or "/root"
local base = os.getenv("DOUYIN_DIR") or (home .. "/douyin")
local d = sec ~= "" and (base .. "/" .. sec) or (base .. "/base")
os.execute("mkdir -p " .. q(d .. "/video") .. " " .. q(d .. "/wav"))

local wf = assert(io.open(d .. "/文案.txt", "w"))
local tf = assert(io.open(d .. "/标签.txt", "w"))
local rows = {}
for _, it in ipairs(list) do
    local desc = tostring(it.desc or "")
    local clean = desc:gsub("#[^# ]+", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local tags = {}
    for tag in desc:gmatch("#[^# ]+") do tags[#tags + 1] = tag end
    local tagstr = table.concat(tags, " ")
    wf:write(string.format("%d | 赞%d | %s\n", it.i or 0, it.digg or 0, clean))
    tf:write(string.format("%d | %s\n", it.i or 0, tagstr))
    rows[#rows + 1] = { i = it.i or 0, id = tostring(it.id or ""), digg = tonumber(it.digg) or 0,
                        url = tostring(it.url or ""), clean = clean, tags = tagstr }
end
wf:close()
tf:close()

if cmd == "list" then
    for _, r in ipairs(rows) do
        print(string.format("%d | 赞%d | %s\t标签: %s", r.i, r.digg, r.clean, r.tags))
    end
    print("（list 模式，未下载；下载用: douyin.sh get " .. n .. "）")
    os.exit(0)
end

print("下载到 " .. d .. "/video ...")
local cook = home .. "/.myagent_douyin_cookie"
local got = 0
for _, r in ipairs(rows) do
    if r.id ~= "" then
        local f = string.format("%s/video/%02d_%s.mp4", d, r.i, r.id)
        if size(f) == 0 and r.url ~= "" then
            os.execute("curl -sL --max-time 180 -e 'https://www.douyin.com/' -A " ..
                q(UA) .. " -b " .. q(cook) .. " -o " .. q(f) .. " " .. q(r.url) ..
                " </dev/null")
        end
        if size(f) > 0 then
            got = got + 1
            if r.digg >= minlike then
                local wav = d .. "/wav/" .. r.id .. ".wav"
                if os.execute("ffmpeg -y -i " .. q(f) ..
                    " -vn -ac 1 -ar 16000 -c:a pcm_s16le " .. q(wav) ..
                    " </dev/null >/dev/null 2>&1") == 0 then
                    print("  wav: 第" .. r.i .. "条 赞" .. r.digg .. " → " .. r.id .. ".wav")
                end
            end
        else
            io.stderr:write("  第" .. r.i .. "条 下载失败\n")
        end
    end
end
print("完成：视频 " .. got .. "/" .. n .. " → " .. d .. "/video/  文案/标签 → " ..
    d .. "/文案.txt,标签.txt  高赞wav → " .. d .. "/wav/")
