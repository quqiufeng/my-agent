-- agentkit/adapters/wordcard.lua — WordCard 专用适配（复用其内置 socket 自动化接口）
local ROOT = os.getenv("WORDCARD_ROOT") or "/opt/WordCard"
local M = {}

function M.wrap()
    package.path = ROOT .. "/gui/flutter/automation/?.lua;" .. package.path
    return require("wordcard")
end

-- 打开一个自动化客户端（记得 :close()）
function M.open() return M.wrap().open() end

-- 一次性调用：local r = M.once("stats")
function M.once(fn, ...)
    local c = M.open()
    local r = c[fn](c, ...)
    c:close()
    return r
end

return M
