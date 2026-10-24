local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local termexec = require("termexec")

local HOST = os.getenv("KINDLE_HOST") or "kindle"
local KUI = os.getenv("KUI") or "/opt/my-agent/agentkit/kindle/boot/test/kui"
local TTSK = os.getenv("TTSK") or "/opt/my-agent/agentkit/kindle/boot/test/say_on_kindle.sh"

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function usage()
    io.stderr:write([=[用法:
  tools/ebook.sh state
  tools/ebook.sh say "读异类" | "下一页" | "上一页" | "跳到第20页" | "第3章" | "下一章" | "字号大" | "目录" | "书架"
  tools/ebook.sh shot [out.png]
  tools/ebook.sh dump
  tools/ebook.sh speak
  tools/ebook.sh books
  tools/ebook.sh test
  tools/ebook.sh log [n]
  tools/ebook.sh restart
]=])
    os.exit(2)
end

local function need_device()
    local rc = termexec.run("ssh -o BatchMode=yes -o ConnectTimeout=6 " ..
        q(HOST) .. " true", 20)
    if rc == nil or rc ~= 0 then
        io.stderr:write("电纸书未连接：请用 USB 连接 Kindle，并确认 `ssh " ..
            HOST .. "` 免密可用\n")
        os.exit(1)
    end
end

local function finish(rc, out)
    io.write(out or "")
    if rc == nil then io.stderr:write("命令超时\n"); os.exit(1) end
    os.exit(rc == 0 and 0 or 1)
end

local cmd = arg[1] or "state"
local start = 2

if cmd == "state" or cmd == "status" then
    need_device()
    finish(termexec.run(q(KUI) .. " state", 30))
elseif cmd == "say" then
    need_device()
    local text = table.concat(arg, " ", 2)
    if text == "" then io.stderr:write("用法: tools/ebook.sh say \"<指令>\"\n"); os.exit(2) end
    finish(termexec.run(q(KUI) .. " say " .. q(text), 40))
elseif cmd == "shot" then
    need_device()
    local out = arg[2] or "/tmp/ebook.png"
    finish(termexec.run(q(KUI) .. " shot " .. q(out), 40))
elseif cmd == "dump" then
    need_device()
    finish(termexec.run(q(KUI) .. " dump", 40))
elseif cmd == "speak" then
    need_device()
    finish(termexec.run(q(KUI) .. " page | " .. q(TTSK), 120))
elseif cmd == "books" then
    need_device()
    finish(termexec.run("ssh -o BatchMode=yes -o ConnectTimeout=6 " ..
        q(HOST) .. " 'ls -1 /mnt/us/documents 2>/dev/null'", 30))
elseif cmd == "test" then
    need_device()
    finish(termexec.run(q(KUI) .. " run /opt/my-agent/agentkit/kindle/boot/test/smoke.lua", 120))
elseif cmd == "log" then
    need_device()
    finish(termexec.run(q(KUI) .. " log " .. q(arg[2] or "30"), 30))
elseif cmd == "restart" then
    need_device()
    finish(termexec.run(q(KUI) .. " restart", 60))
else
    usage()
end
