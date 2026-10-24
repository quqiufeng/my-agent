-- tools/wechat_send.lua — 发送微信文本（LuaJIT + xdo/xclip，无 xdotool）
-- 默认联系人「文件传输助手」，可用 --to 或 WECHAT_TO 覆盖。
local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local Xdo = require("xdo")

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local to, text = os.getenv("WECHAT_TO") or "", ""
local i = 1
while i <= #arg do
    if arg[i] == "--to" then to = arg[i + 1] or ""; i = i + 2
    else
        text = text .. (text ~= "" and " " or "") .. arg[i]
        i = i + 1
    end
end
if to == "" then to = "文件传输助手" end
if text == "" then
    io.stderr:write("用法: wechat_send.sh [--to 联系人] 文本\n")
    os.exit(2)
end

local TAG = os.getenv("WECHAT_AI_TAG") or "ai助手"
local out = text
if not out:find("ai助手") then out = TAG .. " " .. out end

if os.getenv("WECHAT_SEND_DRY") == "1" then
    print("dry-run -> " .. to .. ": " .. out)
    os.exit(0)
end

local d, err = Xdo.new()
if not d then io.stderr:write("xdo: " .. tostring(err) .. "\n"); os.exit(1) end

local function sleep_ms(ms) os.execute("sleep " .. string.format("%.3f", ms / 1000)) end

local wins = d:find("微信")
local target, area = nil, 0
for _, w in ipairs(wins) do
    local g = w.geom
    if g and g.w * g.h > area then target, area = w, g.w * g.h end
end
if not target then
    io.stderr:write("找不到微信窗口\n")
    d:close()
    os.exit(1)
end

local wid = target.id
local function activate()
    d:activate(wid)
    d:raise(wid)
    sleep_ms(800)
    d:click(wid, 100, 20)
    sleep_ms(300)
end

local function paste(s)
    local file = "/tmp/wechat_send_clip_" .. tostring(os.time()) .. ".txt"
    local f = io.open(file, "w")
    if not f then return false end
    f:write(s)
    f:close()
    os.execute("xclip -selection clipboard " .. q(file) .. " </dev/null >/dev/null 2>&1")
    sleep_ms(250)
    d:key(0, "ctrl+v")
    sleep_ms(500)
    os.remove(file)
    return true
end

activate()
-- 搜索并进入目标会话
d:click(wid, 180, 50)
sleep_ms(500)
if not paste(to) then
    io.stderr:write("剪贴板写入失败\n")
    d:close()
    os.exit(1)
end
sleep_ms(300)
d:key(0, "Return")
sleep_ms(1500)
d:key(0, "Return")
sleep_ms(1500)

-- 先记录再发送：供 bridge 避免把大脑回复当成新消息
local log = os.getenv("WECHAT_SENT_LOG") or "/tmp/myagent_wechat_sent.log"
local lf = io.open(log, "a")
if lf then lf:write(out .. "\n"); lf:close() end

-- 点输入框、粘贴、回车
local g = d:geometry(wid)
local gw = (g and g.w) or 2400
local gh = (g and g.h) or 1400
d:click(wid, math.floor(gw * 0.47), math.floor(gh * 0.874))
sleep_ms(300)
paste(out)
d:key(0, "Return")
sleep_ms(400)
d:key(0, "Return")
sleep_ms(400)
-- 最后兜底：点右下角发送按钮（输入为空时禁用，点了无副作用）
d:click(wid, math.floor(gw * 0.965), math.floor(gh * 0.978))

d:close()
print("已发送 -> " .. to)
