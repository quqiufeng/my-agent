-- tools/wechat_shot.lua — 打开目标会话并聚焦输入框（供 Alt+A 截图后粘贴发送）
-- 默认联系人「文件传输助手」，可用 WECHAT_TO 覆盖。
local robot = require("wechat_robot")
local to = os.getenv("WECHAT_TO") or ""
if to == "" then to = "文件传输助手" end

local ok, err = robot.init()
if not ok then io.stderr:write("wechat init 失败: " .. tostring(err) .. "\n"); os.exit(1) end
robot.search(to)
robot.destroy()
print("已进入会话 -> " .. to)
