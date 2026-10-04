-- tools/wechat_send_file.lua — 发送文件/图片（默认当前会话，WECHAT_TO 非空则先搜索联系人）
local robot = require("wechat_robot")
local to = os.getenv("WECHAT_TO") or ""
local file = arg[1] or ""

local ok, err = robot.init()
if not ok then io.stderr:write("wechat init 失败: " .. tostring(err) .. "\n"); os.exit(1) end

if to ~= "" then robot.search(to) end
robot.send_file(file)
robot.destroy()
print("已发送文件")
