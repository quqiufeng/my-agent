-- agentkit/adapters/google.lua — Google 搜索（走 CDP/DOM 精准取结果，非 OCR）
--   local g = ak.app("google")
--   g.search("DeepSeek")
--   for _, r in ipairs(g.results(10)) do print(r.title, r.url) end
--   print(g.text())        -- 可选：整页可见文本
-- 依赖：固定端口 Chrome（tools/chrome_debug.sh）+ agentkit.cdp
local cjson = require("cjson")
local cdp = require("agentkit.cdp")
local M = {}

local function enc(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

-- 搜索：直接导航到结果页
function M.search(q, opts)
    cdp.goto("https://www.google.com/search?q=" .. enc(q))
    return true
end

-- 结构化结果：[{title=, url=}, ...]（取结果标题的 a h3）
function M.results(limit)
    limit = limit or 10
    local js = "JSON.stringify([...document.querySelectorAll('a h3')].map(function(h){" ..
        "var a=h.closest('a');return {title:h.innerText,url:a?a.href:''}}).slice(0," .. limit .. "))"
    local out = cdp.eval(js)
    local ok, res = pcall(cjson.decode, out or "")
    return (ok and type(res) == "table") and res or {}
end

-- 供批量/大脑：一行行文本
function M.read_results(limit)
    local lines = {}
    for _, r in ipairs(M.results(limit)) do
        lines[#lines + 1] = string.format("%s — %s", r.title, r.url)
    end
    return lines
end
M.read = M.read_results

-- 当前页标题 / 可见文本
function M.title() return cdp.title() end
function M.text() return cdp.eval("document.body.innerText") end
function M.url() return cdp.url() end

return M
