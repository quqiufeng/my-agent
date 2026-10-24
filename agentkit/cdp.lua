-- agentkit/cdp.lua — 经常驻 CDP 守护做 DOM 精准操作（Chrome 只授权一次）
-- 守护: agentkit/tools/cdpd.js（连 Chrome 一次并常驻，本机 9333）
-- 客户端: agentkit/tools/cdpc.js（只连本机 9333，不碰 Chrome → 不再弹授权）
local cjson = require("cjson")
local M = {}

local CDPD = os.getenv("AGENTKIT_CDPD") or "/opt/my-agent/agentkit/tools/cdpd.js"
local CDPC = os.getenv("AGENTKIT_CDPC") or "/opt/my-agent/agentkit/tools/cdpc.js"

local function sh(c)
    local f = io.popen(c); local o = f:read("*a") or ""; f:close(); return o
end
local function up() return sh("ss -ltn 2>/dev/null | grep ':9333 '") ~= "" end
M.up = up

-- 首次：启动常驻守护（连 Chrome 一次）；已就绪则绝不重连、绝不重复授权
local _started = false
function M.ensure()
    if up() then return true end
    _started = false
    os.execute(("setsid node %s >/dev/null 2>&1 < /dev/null &"):format(CDPD))
    for _ = 1, 20 do if up() then _started = true; break end; os.execute("sleep 0.5") end
    return up()
end

local function call(cmd, args)
    M.ensure()
    local req = cjson.encode({ cmd = cmd, args = args or {} })
    local f = io.popen(("node %s %q 2>/dev/null"):format(CDPC, req))
    local out = f:read("*a") or ""; f:close()
    return (out:gsub("\n$", ""))
end
M.call = call

function M.title() return call("title") end
function M.url()   return call("url") end
function M.eval(js) return call("eval", { js = js }) end
function M.text(sel) return call("text", { sel = sel }) end
function M.html(sel) return call("html", { sel = sel }) end
function M.query(sel) return call("query", { sel = sel }) end
function M.click(sel) return call("click", { sel = sel }) end
function M.focus(sel) return call("focus", { sel = sel }) end
function M.goto(url) return call("goto", { url = url }) end
function M.cookies(domain) return call("cookies", { domain = domain or "" }) end
function M.type(text) return call("type", { text = text }) end
function M.press() return call("press", {}) end
function M.wait(js, timeout) return call("wait", { js = js, timeout = timeout or 20000 }) end
function M.gemini(prompt) return call("gemini", { prompt = prompt }) end
function M.ask(prompt) return call("ask", { prompt = prompt }) end

return M
