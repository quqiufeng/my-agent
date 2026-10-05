-- tools/wechat_send_file.lua — 发送文件/图片（永远先搜索联系人进入会话再发送）
-- 默认联系人「文件传输助手」，可用 WECHAT_TO 覆盖。
local robot = require("wechat_robot")
local to = os.getenv("WECHAT_TO") or ""
if to == "" then to = "文件传输助手" end
local file = arg[1] or ""

local ok, err = robot.init()
if not ok then io.stderr:write("wechat init 失败: " .. tostring(err) .. "\n"); os.exit(1) end

robot.search(to)
os.execute("sleep 1")   -- 等搜索/焦点/剪贴板稳定

local ext = file:lower():match("%.([%w]+)$") or ""
local is_img = (ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp" or ext == "bmp" or ext == "gif")
if is_img then
    robot.send_image(file)   -- 图片走剪贴板粘贴（稳）
else
    robot.send_file(file)    -- 其它文件走文件对话框
end
robot.destroy()
print("已发送 -> " .. to)
