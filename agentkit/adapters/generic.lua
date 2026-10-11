-- agentkit/adapters/generic.lua — 任意 X11 应用的通用适配（无需被控程序提供接口）
local x11 = require("agentkit.x11")
local M = {}
function M.window(title, opts) return x11.window(title, opts) end
return M
