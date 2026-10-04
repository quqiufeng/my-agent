-- tools/wechat_send.lua — 发送微信文本（默认当前会话，WECHAT_TO 非空则先搜索联系人）
local robot = require("wechat_robot")
local to = os.getenv("WECHAT_TO") or ""
local text = arg[1] or ""

local ok, err = robot.init()
if not ok then io.stderr:write("wechat init 失败: " .. tostring(err) .. "\n"); os.exit(1) end

if to ~= "" then robot.search(to) end

-- 先记录再发送：供 bridge 避免把大脑回复当成新消息（防自循环），并消除时序竞态
local f = io.open(os.getenv("WECHAT_SENT_LOG") or "/tmp/myagent_wechat_sent.log", "a")
if f then f:write(text .. "\n"); f:close() end

robot.send(text)
robot.destroy()
print("已发送")
