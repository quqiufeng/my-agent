#!/usr/bin/env bash
# tools/chrome_auth.sh — Chrome 远程调试授权 + 受控状态（视觉 + MCP 结合）
# @desc 开启 Chrome「允许远程调试」并点掉授权弹窗（视觉）；`status` 查看是否受控
# @usage tools/chrome_auth.sh [enable|consent|watch <秒>|status]
# @rule 浏览器 MCP(chrome-devtools) 连不上/提示授权 → 先 `tools/chrome_auth.sh enable`；仍弹“同意”框用 `consent`（或后台 `watch 60`）；查状态用 `status`。
# @order 18
set -uo pipefail
unset DISPLAY                      # 让 agentkit 自动从图形会话派生 DISPLAY/XAUTHORITY
export AK_CMD="${1:-enable}"
export AK_SEC="${2:-30}"
exec luajit -e '
package.path="/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;"..package.path
local ak=require("agentkit"); local ch=ak.app("chrome")
local a=os.getenv("AK_CMD") or "enable"
if a=="enable" then
  local ok,m=ch.enable_remote_debugging()
  print(ok and ("已授权: "..tostring(m)) or ("未成功: "..tostring(m))); os.exit(ok and 0 or 1)
elseif a=="consent" then
  local ok,m=ch.accept_consent(); print(ok and ("已点同意: "..tostring(m)) or "无同意框")
elseif a=="watch" then
  local ok=ch.watch_consent(tonumber(os.getenv("AK_SEC") or "30")); print(ok and "已点同意" or "超时未见")
elseif a=="status" then
  local bar=ch.controlled_bar()
  print("端口9222: "..tostring(ch.port_open(9222)))
  print("受控状态: "..(bar and ("是（"..tostring(bar).."）") or "否"))
else
  io.stderr:write("用法: chrome_auth.sh [enable|consent|watch <秒>|status]\n"); os.exit(2)
end
'
