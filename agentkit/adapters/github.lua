-- agentkit/adapters/github.lua — GitHub Trending 采集（每日监控）
--   local gh = ak.app("github")
--   local list = gh.trending({since="daily", limit=20})
--   gh.save_daily()                     -- 追加到按天的记录文件（供长期对比/监控）
--
-- 与 google/gemini 不同：trending 是服务端渲染 HTML、无需登录，故用
-- curl 取 HTML + 就地解析（LuaJIT），比像素 OCR 稳定得多；页面结构由浏览器探索确认。
local M = {}

local URL = "https://github.com/trending"
local DIR = os.getenv("AGENTKIT_GH_DIR") or "/opt/my-agent/agentkit/results"

local function sh(cmd)
    local f = io.popen(cmd)
    if not f then return "" end
    local o = f:read("*a") or ""
    f:close()
    return o
end

local function unescape(s)
    s = s:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&#39;", "'"):gsub("&quot;", '"')
    s = s:gsub("<[^>]->", "")           -- 去内联标签
    s = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    return s
end

local function fetch(url)
    return sh(("curl -sL --max-time 30 %q"):format(url))
end

-- opts = { since="daily|weekly|monthly", lang="lua", limit=N }
function M.trending(opts)
    opts = opts or {}
    local since = opts.since or "daily"
    local url = URL
    if opts.lang and opts.lang ~= "" then url = url .. "/" .. opts.lang end
    url = url .. "?since=" .. since
    local html = fetch(url)
    local out = {}
    for block in html:gmatch('<article class="Box%-row">(.-)</article>') do
        local repo = block:match('<h2[^>]*>%s*<a[^>]-href="/([%w%._%-]+/[%w%._%-]+)"')
        if repo then
            local desc = block:match('<p class="[^"]*col%-9[^"]*"[^>]*>(.-)</p>') or ""
            local lang = block:match('itemprop="programmingLanguage">([^<]+)<') or ""
            local stars_today = block:match('([%d,]+)%s*stars today') or "0"
            local stars = block:match('stargazers"[^>]*>%s*([%d,]+)') or ""
            local forks = block:match('/forks"[^>]*>%s*([%d,]+)') or ""
            out[#out + 1] = {
                rank = #out + 1,
                repo = repo,
                url = "https://github.com/" .. repo,
                lang = lang,
                stars = stars:gsub(",", ""),
                stars_today = tonumber((stars_today:gsub(",", ""))) or 0,
                forks = forks:gsub(",", ""),
                desc = unescape(desc),
            }
            if opts.limit and #out >= opts.limit then break end
        end
    end
    return out
end

-- 供 batch 复用
function M.read(opts) return M.trending(opts) end
M.read_results = M.read

-- 一行摘要（含排名）
function M.brief(opts)
    local lines = {}
    for _, r in ipairs(M.trending(opts)) do
        lines[#lines + 1] = string.format("%2d. %-40s +%-6d [%s] %s",
            r.rank, r.repo, r.stars_today, r.lang, r.desc)
    end
    return lines
end

-- 每日记录：追加到 results/trending-YYYY-MM-DD.lua 与 .jsonl（长期监控/对比）
function M.save_daily(opts)
    local cjson = require("cjson")
    opts = opts or {}
    local list = M.trending(opts)
    local day = os.date("%Y-%m-%d")
    os.execute("mkdir -p " .. DIR)
    local jf = io.open(DIR .. "/trending-" .. day .. ".jsonl", "w")
    for _, r in ipairs(list) do
        r.date = day
        jf:write(cjson.encode(r), "\n")
    end
    jf:close()
    return DIR .. "/trending-" .. day .. ".jsonl", #list
end

return M
