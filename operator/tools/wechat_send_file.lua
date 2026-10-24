-- tools/wechat_send_file.lua — 发送文件/图片（永远先搜索联系人进入会话再发送）
-- 默认联系人「文件传输助手」，可用 WECHAT_TO 覆盖。
local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local bg = require("bgjob")

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local file = arg[1] or ""
if file == "" then
    io.stderr:write("用法: wechat_send_file.sh <文件路径|URL> [--to 联系人]\n")
    os.exit(2)
end

if file:match("^https?://") and os.getenv("BG_WORKER") ~= "1"
    and os.getenv("WECHAT_SEND_FILE_FG") ~= "1" then
    local j = bg.spawn_self(arg, "wechat_send_file")
    print("已后台下载并发送 job=" .. j.id)
    print("查看进度: tools/jobs.sh tail " .. j.id)
    os.exit(0)
end

if file:match("^https?://") then
    require("dotenv").load()
    local raw = (file:gsub("%?.*$", ""):match("([^/]+)$")) or "download"
    local dec = raw:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end):gsub("[/\\]", "_")
    local out = "/tmp/myagent_dl_" .. os.time() .. "_" .. dec
    local home = os.getenv("HOME") or "/root"
    local cmd = "curl -fsSL -m 300 --netrc-file " .. q(home .. "/.webdav_netrc") ..
        " -o " .. q(out) .. " " .. q(file)
    if os.execute(cmd) ~= 0 then
        io.stderr:write("下载失败: " .. file .. "\n")
        os.exit(1)
    end
    file = out
end

local f = io.open(file, "rb")
if not f then
    io.stderr:write("文件不存在: " .. file .. "\n")
    os.exit(2)
end
f:close()

if os.getenv("WECHAT_SEND_FILE_DRY") == "1" then
    print(file)
    os.exit(0)
end

local robot = require("wechat_robot")
local to = os.getenv("WECHAT_TO") or ""
if to == "" then to = "文件传输助手" end

local ok, err = robot.init()
if not ok then io.stderr:write("wechat init 失败: " .. tostring(err) .. "\n"); os.exit(1) end

robot.search(to)
os.execute("sleep 1")

local ext = file:lower():match("%.([%w]+)$") or ""
local is_img = (ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp" or ext == "bmp")
if is_img then
    robot.send_image(file)
else
    robot.send_file(file)
end
robot.destroy()
print("已发送 -> " .. to)
