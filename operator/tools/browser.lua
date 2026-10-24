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
