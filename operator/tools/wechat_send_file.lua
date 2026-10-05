-- tools/wechat_send_file.lua — 发送文件/图片（永远先搜索联系人进入会话再发送）
-- 默认联系人「文件传输助手」，可用 WECHAT_TO 覆盖。
local robot = require("wechat_robot")
local to = os.getenv("WECHAT_TO") or ""
if to == "" then to = "文件传输助手" end
local file = arg[1] or ""

local ok, err = robot.init()
if not ok then io.stderr:write("wechat init 失败: " .. tostring(err) .. "\n"); os.exit(1) end

robot.search(to)
robot.send_file(file)
robot.destroy()
print("已发送文件 -> " .. to)
