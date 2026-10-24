local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path

local cjson = require("cjson")
local bg = require("bgjob")
local REPORT = "/opt/my-agent/operator/report"
local CORE_CDP = "/opt/my-agent/agentkit/tools/cdp.js"

local SOURCES = {
    "https://hnrss.org/frontpage",
    "https://feeds.arstechnica.com/arstechnica/index",
    "https://techcrunch.com/feed/",
    "https://www.theregister.com/headlines.atom",
    "https://www.engadget.com/rss.xml",
    "https://www.theverge.com/rss/index.xml",
    "https://www.wired.com/feed/rss",
    "http://feeds.bbci.co.uk/news/technology/rss.xml",
    "https://www.technologyreview.com/feed/",
}

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function urlencode(s)
    return (s:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local topic, url, words, level = "", "", 180, "B1-B2"
local display, to, send = false, "文件传输助手", true
local fg = false
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--url" then url = arg[i + 1] or ""; i = i + 2
    elseif a == "--words" then words = tonumber(arg[i + 1]) or 180; i = i + 2
    elseif a == "--level" then level = arg[i + 1] or "B1-B2"; i = i + 2
    elseif a == "--display" then display = true; send = false; i = i + 1
    elseif a == "--to" then to = arg[i + 1] or "文件传输助手"; i = i + 2
    elseif a == "--no-send" then send = false; i = i + 1
    elseif a == "--fg" then fg = true; i = i + 1
    else
        if topic == "" then topic = a end
        i = i + 1
    end
end

if not display and not fg and os.getenv("BG_WORKER") ~= "1" then
    local j = bg.spawn_self(arg, "english_daily")
    print("已后台生成每日英语 job=" .. j.id)
    print("查看进度: tools/jobs.sh tail " .. j.id)
    os.exit(0)
end

local function ensure_chrome()
    if os.execute("ss -ltn 2>/dev/null | grep -q ':9222 '") ~= 0 then
        os.execute(q(DIR .. "/chrome_debug.sh") .. " >/dev/null 2>&1")
        os.execute("sleep 2")
    end
end

local EXTRACT = [[(()=>{const r=document.querySelector("article")||document.querySelector("main")||document.body;const ps=[...r.querySelectorAll("p")].map(p=>p.innerText.trim()).filter(t=>t.length>40);return ps.join("\n\n")})()]]

local function extract_article(u)
    ensure_chrome()
    os.execute("node " .. q(CORE_CDP) .. " goto " .. q(u) .. " >/dev/null 2>&1")
    os.execute("sleep 4")
    local p = io.popen("node " .. q(CORE_CDP) .. " eval " .. q(EXTRACT) .. " 2>/dev/null")
    local t = p and p:read("*a") or ""
    if p then p:close() end
    if #t >= 700 then return t end
    return nil
end

local function feed_urls(feed)
    local p = io.popen("curl -sL --max-time 20 " .. q(feed) .. " 2>/dev/null")
    local xml = p and p:read("*a") or ""
    if p then p:close() end
    local out, seen = {}, {}
    for block in xml:gmatch("<[Ii]tem[^>]*>(.-)</[Ii]tem>") do
        local u = block:match('<link[^>]*href="([^"]+)"') or block:match("<link[^>]*>([^<]+)</link>")
        if u and u:match("^https?://") and not seen[u] then
            seen[u] = true; out[#out + 1] = u
        end
    end
    for block in xml:gmatch("<entry[^>]*>(.-)</entry>") do
        local u = block:match('<link[^>]*href="([^"]+)"')
        if u and u:match("^https?://") and not seen[u] then
            seen[u] = true; out[#out + 1] = u
        end
    end
    return out
end

local function shuffle(t)
    for n = #t, 2, -1 do
        local j = math.random(n)
        t[n], t[j] = t[j], t[n]
    end
end

local function get_passage()
    if url ~= "" then
        local t = extract_article(url)
        if t then return t .. "\nSRCURL " .. url end
        return ""
    end
    if topic ~= "" then
        local api = "https://en.wikipedia.org/w/api.php?action=query&format=json&prop=extracts&explaintext=1&exlimit=1&redirects=1&titles=" ..
            urlencode(topic)
        local p = io.popen("curl -s --max-time 20 " .. q(api) .. " 2>/dev/null")
        local raw = p and p:read("*a") or ""
        if p then p:close() end
        local ok, res = pcall(cjson.decode, raw)
        local pages = ok and res and res.query and res.query.pages or nil
        if pages then
            for _, page in pairs(pages) do
                if page.extract and page.extract ~= "" then
                    return page.extract .. "\nSRCURL https://en.wikipedia.org/wiki/" .. topic
                end
            end
        end
        return ""
    end

    local feeds = {}
    for _, s in ipairs(SOURCES) do feeds[#feeds + 1] = s end
    shuffle(feeds)
    for n = 1, math.min(4, #feeds) do
        local urls = feed_urls(feeds[n])
        for m = 1, math.min(4, #urls) do
            local t = extract_article(urls[m])
            if t then return t .. "\nSRCURL " .. urls[m] end
        end
    end
    return ""
end

local raw = get_passage()
local src = raw:match("SRCURL%s+([^\n]+)") or ""
local pass = raw:gsub("SRCURL%s+[^\n]+\n?", ""):sub(1, 4000)
local wl = {}
for word in pass:gmatch("%S+") do
    wl[#wl + 1] = word
    if #wl >= words then break end
end
pass = table.concat(wl, " ")
if #wl < 40 then io.stderr:write("未取到英文文章\n"); os.exit(1) end
io.stderr:write("来源: " .. src .. "\n")

local stamp = os.date("%Y%m%d_%H%M%S")
local out = "/tmp/myagent_en_" .. stamp
local prompt = 'You are an English-learning assistant. Given the English passage, output ONLY minified JSON (no markdown, no extra words) with shape {"title_en":"","title_zh":"","paras":[{"en":"...","zh":"..."}],"vocab":[{"word":"...","zh":"..."}]}. Split into 2-4 paragraphs, translate each to natural Simplified Chinese, pick 6-8 useful words (level ' ..
    level .. ') with short Chinese meanings. Passage: ' .. pass

local pf = io.open(out .. ".prompt", "w")
if pf then pf:write(prompt); pf:close() end

os.execute("GEMINI_NEW_TARGET=1 timeout 200 node /opt/my-agent/agentkit/tools/gemini.js " ..
    q(prompt) .. " > " .. q(out .. ".json") .. " 2>/dev/null")
local js = read_file(out .. ".json") or ""
js = js:gsub("^```[a-z]*\n?", ""):gsub("\n?```%s*$", "")
if not js:find('"paras"', 1, true) then
    io.stderr:write("翻译失败（无 JSON）\n")
    os.exit(1)
end
local jf = io.open(out .. ".json", "w")
if jf then jf:write(js); jf:close() end

os.execute("luajit " .. q(REPORT .. "/english_article.lua") .. " " ..
    q(out .. ".html") .. " " .. q(out .. ".txt") .. " " .. q(out .. ".json") .. " " .. q(src))

local tf = read_file(out .. ".txt") or ""
if display then io.write(tf); os.exit(0) end
io.write(tf)

os.execute(q(REPORT .. "/render.sh") .. " " .. q(out .. ".html") .. " " ..
    q(out .. ".png") .. " 820 >/dev/null 2>&1")
print("图片: " .. out .. ".png")

if send then
    local f = io.open(out .. ".png", "rb")
    if f then
        f:close()
        if os.execute(q(DIR .. "/wechat_send_file.sh") .. " " .. q(out .. ".png") ..
            " --to " .. q(to) .. " >/dev/null 2>&1") == 0 then
            print("已发图片 → " .. to)
        end
    end
end
