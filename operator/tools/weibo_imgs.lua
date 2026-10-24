local DIR = (arg[0] or ""):match("^(.*)/") or "."

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function urlencode(s)
    return (s:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local to, save, each, limit = "", nil, false, nil
local kw, pstart, pend = nil, 1, 20
local refresh = false

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--refresh-cookie" then refresh = true; i = i + 1
    elseif a == "--to" then to = arg[i + 1] or ""; i = i + 2
    elseif a == "--save" then save = arg[i + 1]; i = i + 2
    elseif a == "--each" then each = true; i = i + 1
    elseif a == "--limit" then limit = arg[i + 1]; i = i + 2
    elseif a == "all" or a == "全部" then pend = 0; i = i + 1
    elseif a:match("^%d+%-%d+$") then
        pstart, pend = tonumber(a:match("^(%d+)")), tonumber(a:match("(%d+)$"))
        i = i + 1
    elseif a:match("^%d+$") then
        if not kw then kw = a else pend = tonumber(a) or pend end
        i = i + 1
    else
        if not kw then kw = a end
        i = i + 1
    end
end

if not kw or kw == "" then
    io.stderr:write("用法: weibo_imgs.sh <明星/关键词> [页数或 A-B] [--save 目录] [--each] [--limit N] [--to 会话]\n")
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
    if out then out:write(table.concat(lines, "\n"), "\n"); out:close() end
    return ck
end

local cookie = os.getenv("WEIBO_COOKIE") or ""
if cookie == "" then
    local f = io.open(cache, "r")
    if f then cookie = (f:read("*a") or ""):gsub("%s+$", ""); f:close() end
end
if refresh or cookie == "" then cookie = refresh_cookie() or cookie end
if cookie == "" then
    io.stderr:write("没有微博 cookie。运行一次: weibo_imgs.sh --refresh-cookie（需已登录 Chrome）\n")
    os.exit(3)
end

local ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
local enc = urlencode(kw)
local urls, seen = {}, {}
local maxpage = tonumber(os.getenv("WEIBO_MAX_PAGE")) or 40

local function fetch_page(p)
    local url = "https://s.weibo.com/weibo?q=" .. enc .. "&page=" .. p
    local pipe = io.popen("curl -s --max-time 25 -A " .. q(ua) ..
        " -H 'Referer: https://s.weibo.com/' -b " .. q(cookie) ..
        " " .. q(url) .. " 2>/dev/null")
    local html = pipe and pipe:read("*a") or ""
    if pipe then pipe:close() end
    local before = #urls
    for ids in html:gmatch("pic_ids=([^\"&<]*)") do
        for id in ids:gmatch("[^,]+") do
            if id ~= "" then
                local u = "https://wx1.sinaimg.cn/large/" .. id .. ".jpg"
                if not seen[u] then seen[u] = true; urls[#urls + 1] = u end
            end
        end
    end
    return #urls - before
end

local range
if pend == 0 then
    local p, empty, last = pstart, 0, pstart
    while p <= maxpage do
        io.stderr:write("  · 抓第 " .. p .. " 页...\n")
        local added = fetch_page(p)
        last = p
        if added <= 0 then empty = empty + 1 else empty = 0 end
        if empty >= 2 then break end
        p = p + 1
    end
    range = pstart .. ".." .. last
else
    for p = pstart, pend do
        io.stderr:write("  · 抓第 " .. p .. " 页...\n")
        fetch_page(p)
    end
    range = pstart .. ".." .. pend
end

print("抓到 " .. #urls .. " 张图 URL（页 " .. range .. "）")
if #urls == 0 then
    io.stderr:write("没抓到图（检查 Chrome 是否登录、cookie 是否失效）\n")
    os.exit(1)
end

local listfile = "/tmp/wb_imgs_urls_" .. tostring(os.time()) .. ".txt"
local lf = assert(io.open(listfile, "w"))
lf:write(table.concat(urls, "\n"), "\n")
lf:close()

local args = { q(DIR .. "/send_images.sh") }
if each then args[#args + 1] = "--each" end
if limit and limit ~= "" then args[#args + 1] = "--limit"; args[#args + 1] = q(limit) end
if to ~= "" then
    args[#args + 1] = "--to"; args[#args + 1] = q(to)
else
    local outdir = save or (home .. "/微博图/" .. kw)
    args[#args + 1] = "--save"; args[#args + 1] = q(outdir)
    os.execute("SAVE_PREFIX=" .. q(os.date("%m%d_%H%M%S") .. "_") .. " " ..
        table.concat(args, " ") .. " < " .. q(listfile))
    os.remove(listfile)
    os.exit(0)
end
os.execute(table.concat(args, " ") .. " < " .. q(listfile))
os.remove(listfile)
