#!/usr/bin/env bash
# tools/browser.sh — 操作本机 Chrome（不新开浏览器）
# 用法: browser.sh new_tab
#       browser.sh open <url>
#       browser.sh search <关键词>
#       browser.sh ai_search <问题>
#       browser.sh screenshot [输出路径]
set -uo pipefail
export LD_LIBRARY_PATH="/opt/my-agent/wechat-ocr/lib:${LD_LIBRARY_PATH:-}"
export LUA_PATH="/opt/my-agent/wechat-ocr/lua/?.lua;/opt/my-agent/wechat-ocr/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;"
export DISPLAY="${DISPLAY:-:0}"

exec luajit -e '
local c = require("wechat_ocr.chrome")
local a = arg[1]
if a == "new_tab" then
    c.new_tab()
elseif a == "open" then
    c.open(arg[2] or "")
elseif a == "search" then
    c.search(arg[2] or "")
elseif a == "ai_search" then
    c.ai_search(arg[2] or "")
elseif a == "screenshot" then
    local p = c.screenshot(arg[2])
    print(p or "/tmp/chrome_ss.png")
else
    io.stderr:write("用法: browser.sh new_tab|open <url>|search <kw>|ai_search <q>|screenshot [path]\n")
    os.exit(2)
end
' "$@"
