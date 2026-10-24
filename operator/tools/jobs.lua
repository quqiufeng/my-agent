local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local bg = require("bgjob")

local cmd = arg[1] or "list"

if cmd == "list" then
    local rows = bg.list()
    if #rows == 0 then print("（没有后台任务）"); os.exit(0) end
    for _, row in ipairs(rows) do print(row) end
elseif cmd == "tail" then
    local id = arg[2]
    if not id then io.stderr:write("用法: jobs.sh tail <id> [行数]\n"); os.exit(2) end
    print("status: " .. bg.status(id))
    print(bg.tail(id, tonumber(arg[3]) or 30))
elseif cmd == "stop" then
    local id = arg[2]
    if not id then io.stderr:write("用法: jobs.sh stop <id>\n"); os.exit(2) end
    local ok, err = bg.stop(id)
    if not ok then io.stderr:write(err .. "\n"); os.exit(1) end
    print("已停止 " .. id)
elseif cmd == "status" then
    local id = arg[2]
    if not id then io.stderr:write("用法: jobs.sh status <id>\n"); os.exit(2) end
    print(bg.status(id))
else
    io.stderr:write("用法: jobs.sh list | tail <id> [行数] | stop <id> | status <id>\n")
    os.exit(2)
end
