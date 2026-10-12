-- tools/wechat_send.lua — 发送微信文本（永远走完整流程：搜索联系人→进入会话→输入→回车）
-- 默认联系人「文件传输助手」，可用 WECHAT_TO 覆盖。
local robot = require("wechat_robot")
local to = os.getenv("WECHAT_TO") or ""
if to == "" then to = "文件传输助手" end
local text = arg[1] or ""

-- 回复统一带「ai助手」前缀，便于在聊天里区分 AI 的回复（# 可省）
local TAG = os.getenv("WECHAT_AI_TAG") or "ai助手"
local out = text
if not out:find("ai助手") then out = TAG .. " " .. text end

local ok, err = robot.init()
if not ok then io.stderr:write("wechat init 失败: " .. tostring(err) .. "\n"); os.exit(1) end

-- 完整流程：搜索并进入目标会话（不依赖当前窗口是否已打开）
robot.search(to)

-- 先记录再发送：供 bridge 避免把大脑回复当成新消息（防自循环），并消除时序竞态
local f = io.open(os.getenv("WECHAT_SENT_LOG") or "/tmp/myagent_wechat_sent.log", "a")
if f then f:write(out .. "\n"); f:close() end

robot.send(out)
-- 兜底：确保提交（点输入框聚焦 + 回车两次；空回车无副作用）
os.execute("sleep 0.6")
local win = robot.get_window_rect()
if win then
    local cx = win.x + math.floor(win.w * 0.47)
    local cy = win.y + math.floor(win.h * 0.874)
    os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", cx, cy))
    os.execute("sleep 0.3")
    os.execute("xdotool key --clearmodifiers Return 2>/dev/null")
    os.execute("sleep 0.3")
    os.execute("xdotool key --clearmodifiers Return 2>/dev/null")
end
robot.destroy()
print("已发送 -> " .. to)
