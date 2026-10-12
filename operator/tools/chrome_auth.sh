#!/usr/bin/env bash
# tools/chrome_auth.sh — 开启 Chrome 远程调试授权（视觉点复选框），供 chrome-devtools MCP 使用
# @desc 确保 Chrome「允许远程调试」已开：视觉打开 chrome://inspect 复选框，使 9222 端口就绪，MCP 才能连
# @usage tools/chrome_auth.sh [enable|consent|watch <秒>]
# @rule 浏览器 MCP(chrome-devtools) 连不上 / 提示需要授权时 → 先 `tools/chrome_auth.sh enable`；若仍弹“同意”框，用 `consent`（或后台 `watch 60`）。
# @order 18
set -uo pipefail
unset DISPLAY                      # 让 agentkit 自动从图形会话派生 DISPLAY/XAUTHORITY
exec luajit -e '
package.path="/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;"..package.path
local ak=require("agentkit"); local ch=ak.app("chrome")
local a=arg[1] or "enable"
if a=="enable" then
  local ok,m=ch.enable_remote_debugging()
  print(ok and ("已授权: "..tostring(m)) or ("未成功: "..tostring(m))); os.exit(ok and 0 or 1)
elseif a=="consent" then
  local ok,m=ch.accept_consent(); print(ok and ("已点同意: "..tostring(m)) or "无同意框")
elseif a=="watch" then
  local ok=ch.watch_consent(tonumber(arg[2] or "30")); print(ok and "已点同意" or "超时未见")
else
  io.stderr:write("用法: chrome_auth.sh [enable|consent|watch <秒>]\n"); os.exit(2)
end
' "$@"
