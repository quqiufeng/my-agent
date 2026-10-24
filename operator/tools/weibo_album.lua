local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
require("dotenv").load()

local cjson = require("cjson")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function urlencode(s)
    return (s:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local to, save, limit, kw, pages = "", nil, nil, nil, 20
local refresh = false
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--to" then to = arg[i + 1] or ""; i = i + 2
    elseif a == "--save" then save = arg[i + 1]; i = i + 2
    elseif a == "--limit" then limit = arg[i + 1]; i = i + 2
    elseif a == "--refresh-cookie" then refresh = true; i = i + 1
    elseif a == "all" or a == "全部" then pages = 0; i = i + 1
    elseif a:match("^%d+$") then
        if not kw then kw = a else pages = tonumber(a) or pages end
        i = i + 1
    else
        if not kw then kw = a end
        i = i + 1
    end
end

if not kw or kw == "" then
    io.stderr:write("用法: weibo_album.sh <昵称|uid> [页数|all，默认20] [--save 目录] [--to 会话] [--limit N]\n")
    os.exit(2)
end

local home = os.getenv("HOME") or "/root"
local cache = os.getenv("WEIBO_COOKIE_FILE") or (home .. "/.myagent_weibo_cookie")

local function refresh_cookie()
    local tmp = "/tmp/myagent_weibo_cookie_" .. tostring(os.time())
    os.execute("node " .. q(DIR .. "/weibo_cookies.js") .. " > " .. q(tmp) .. " 2>/dev/null")
    local f = io.open(tmp, "r")
    local ck = f and (f:read("*a") or "") or ""
    if f then f:close() end
    os.remove(tmp)
    ck = ck:gsub("%s+$", "")
    if ck == "" then return nil end
    local cf = io.open(cache, "w")
    if cf then cf:write(ck); cf:close() end
    local envf = io.open(home .. "/.env", "r")
    local lines = {}
    if envf then
        for line in envf:lines() do
            if not line:match("^WEIBO_COOKIE=") then lines[#lines + 1] = line end
        end
        envf:close()
    end
    lines[#lines + 1] = "WEIBO_COOKIE='" .. ck:gsub("'", "'\\''") .. "'"
    local out = io.open(home .. "/.env", "w")
    if out then
        out:write(table.concat(lines, "\n"), "\n")
        out:close()
    end
    return ck
end

local cookie = os.getenv("WEIBO_COOKIE") or ""
if cookie == "" then
    local f = io.open(cache, "r")
    if f then cookie = (f:read("*a") or ""):gsub("%s+$", ""); f:close() end
end
if refresh or cookie == "" then cookie = refresh_cookie() or cookie end
if cookie == "" then
    io.stderr:write("没有微博 cookie。先跑: weibo_imgs.sh --refresh-cookie（需已登录 Chrome）\n")
    os.exit(3)
end

local ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
local function get(referer, url)
    local p = io.popen("curl -s --max-time 25 -A " .. q(ua) ..
        " -H " .. q("Referer: " .. referer) .. " -b " .. q(cookie) ..
        " " .. q(url) .. " 2>/dev/null")
    local raw = p and p:read("*a") or ""
    if p then p:close() end
    return raw
end

local uid, name
if kw:match("^%d+$") then
    uid = kw
else
    local html = get("https://s.weibo.com/", "https://s.weibo.com/weibo?q=" .. urlencode(kw))
    local matches, seen = {}, {}
    for id, nm in html:gmatch('href="//weibo%.com/u/(%d+)" class="name"[^>]*>([^<]*)') do
        if not seen[id] then
            seen[id] = true
            matches[#matches + 1] = { id = id, name = nm }
        end
    end
    if #matches == 0 then
        io.stderr:write("没搜到用户「" .. kw .. "」（cookie 失效？试 --refresh-cookie）\n")
        os.exit(1)
    end
    local pick
    for n = 1, math.min(5, #matches) do
        if matches[n].name == kw then pick = matches[n]; break end
    end
    pick = pick or matches[1]
    uid, name = pick.id, pick.name
end

local info = get("https://weibo.com/u/" .. uid, "https://weibo.com/ajax/profile/info?uid=" .. uid)
local ok, res = pcall(cjson.decode, info)
local sn = ok and res and res.data and res.data.user and res.data.user.screen_name or nil
if sn and sn ~= "" then name = sn end
name = name or kw
print("目标：" .. name .. " （uid=" .. uid .. "）")

local urls, seen = {}, {}
local since, page, stale, prev = "0", 0, 0, 0
local maxpage = tonumber(os.getenv("WEIBO_ALBUM_MAX_PAGE")) or 60

while true do
    page = page + 1
    if pages > 0 and page > pages then break end
    if page > maxpage then
        io.stderr:write("  · 达到页数上限 " .. maxpage .. "\n")
        break
    end
    local resp = get("https://weibo.com/u/" .. uid,
        "https://weibo.com/ajax/profile/getImageWall?uid=" .. uid .. "&sinceid=" .. since)
    local ok2, r = pcall(cjson.decode, resp)
    local list = ok2 and r and r.data and r.data.list or nil
    if not list or #list == 0 then
        if page == 1 then io.stderr:write("相册为空或接口异常（cookie 失效？）\n") end
        break
    end
    for _, it in ipairs(list) do
        if it.type == "pic" and it.pid and it.pid ~= "" then
            local u = "https://wx1.sinaimg.cn/large/" .. it.pid .. ".jpg"
            if not seen[u] then seen[u] = true; urls[#urls + 1] = u end
        end
    end
    since = tostring((r.data and r.data.since_id) or "null")
    local cur = #urls
    io.stderr:write("  · 第 " .. page .. " 页 +" .. #list .. "（累计 " .. cur .. "）\n")
    if cur <= prev then stale = stale + 1 else stale = 0 end
    prev = cur
    if stale >= 2 then io.stderr:write("  · 连续 2 页无新增，结束\n"); break end
    if since == "" or since == "null" then break end
end

print("相册共 " .. #urls .. " 张大图（页 1.." .. page .. "）")
if #urls == 0 then os.exit(1) end

local cache = home .. "/.cache/myagent"
os.execute("mkdir -p " .. q(cache))
local listfile = cache .. "/wb_album_urls_" .. tostring(os.time()) .. ".txt"
local lf = assert(io.open(listfile, "w"))
lf:write(table.concat(urls, "\n"), "\n")
lf:close()

local args = { q(DIR .. "/send_images.sh") }
if limit and limit ~= "" then args[#args + 1] = "--limit"; args[#args + 1] = q(limit) end
local outdir = save or (home .. "/微博图/" .. name)
args[#args + 1] = "--save"; args[#args + 1] = q(outdir)
if to ~= "" then
    args[#args + 1] = "--to"; args[#args + 1] = q(to)
end
os.execute("SAVE_PREFIX=" .. q(os.date("%m%d_%H%M%S") .. "_") .. " " ..
    table.concat(args, " ") .. " < " .. q(listfile))
os.remove(listfile)
