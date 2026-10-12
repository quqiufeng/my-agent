-- agentkit/cdp.lua — 通过 CDP 精准操作 DOM（无需 MCP）：title/url/eval/text/html/query/click/goto/cookies
-- 底层: agentkit/tools/cdp.js（node，连 DevToolsActivePort 浏览器 WS）
-- 注意: 每次新连接 Chrome 会弹「允许远程调试」授权；本模块会确保「授权守望 daemon」在跑，
--       从而自动点掉弹窗（也可手动 `tools/chrome_auth.sh daemon`）。
local M = {}

local BRIDGE = os.getenv("AGENTKIT_CDP") or "/opt/my-agent/agentkit/tools/cdp.js"
local AUTH = os.getenv("AGENTKIT_CHROME_AUTH") or "/opt/my-agent/operator/tools/chrome_auth.sh"

local function ensure_daemon()
    if os.getenv("AGENTKIT_CDP_NODAEMON") == "1" then return end
    local f = io.popen("pgrep -f 'chrome_auth.sh daemon' | head -1")
    local pid = (f:read("*a") or ""):gsub("%s", ""); f:close()
    if pid == "" and io.open(AUTH, "r") then
        os.execute(("nohup %s daemon >/dev/null 2>&1 &"):format(AUTH))
        os.execute("sleep 1")
    end
end

local function run(cmd, arg)
    ensure_daemon()
    local q = (arg ~= nil and arg ~= "") and (" " .. string.format("%q", arg)) or ""
    local f = io.popen(("node %s %s%s 2>/dev/null"):format(BRIDGE, cmd, q))
    local out = f:read("*a"); f:close()
    return (out:gsub("\n$", ""))
end
M.run = run

function M.title() return run("title") end
function M.url()   return run("url") end
function M.eval(js) return run("eval", js) end
function M.text(sel) return run("text", sel) end
function M.html(sel) return run("html", sel) end
function M.query(sel) return run("query", sel) end
function M.click(sel) return run("click", sel) end
function M.goto(url) return run("goto", url) end
function M.cookies(domain) return run("cookies", domain or "") end

return M
