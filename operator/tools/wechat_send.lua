-- tools/wechat_send.lua — 发送微信文本（永远走完整流程：搜索联系人→进入会话→输入→回车）
-- 默认联系人「文件传输助手」，可用 WECHAT_TO 覆盖。
local robot = require("wechat_robot")
local to = os.getenv("WECHAT_TO") or ""
if to == "" then to = "文件传输助手" end
local text = arg[1] or ""

local ok, err = robot.init()
if not ok then io.stderr:write("wechat init 失败: " .. tostring(err) .. "\n"); os.exit(1) end

-- 完整流程：搜索并进入目标会话（不依赖当前窗口是否已打开）
robot.search(to)

-- 先记录再发送：供 bridge 避免把大脑回复当成新消息（防自循环），并消除时序竞态
local f = io.open(os.getenv("WECHAT_SENT_LOG") or "/tmp/myagent_wechat_sent.log", "a")
if f then f:write(text .. "\n"); f:close() end

robot.send(text)
robot.destroy()
print("已发送 -> " .. to)
