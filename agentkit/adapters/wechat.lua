-- agentkit/adapters/wechat.lua — 微信自动化 API（基于 maps/wechat.lua 的命名区域）
-- 高层用法：
--   local wx = ak.app("wechat")
--   wx.open_chat("文件传输助手")
--   wx.send("你好")
--   local lines = wx.read()
local map = require("agentkit.map")
local x11 = require("agentkit.x11")
local M = {}

local m = map.load("wechat")
M.map = m

local function sleep(s) os.execute("sleep " .. tostring(s or 0.3)) end

function M.window() return m:window() end
function M.click(name) return m:click(name) end
function M.read_region(name) return m:ocr(name) end

-- 打开/搜索一个会话（点搜索框 → 清空 → 粘贴名字 → 回车）
function M.open_chat(name)
    local w = m:window()
    if not w then return false, "no window" end
    w:activate(); sleep(0.3)
    m:click("search_box", w); sleep(0.3)
    w:key("ctrl+a"); w:key("BackSpace"); sleep(0.2)
    x11.paste(name); sleep(0.7)
    w:key("Return"); sleep(0.9)
    return true
end

-- 在当前会话发送文本（点输入框 → 清空 → 粘贴 → 回车）；剪贴板绕过输入法
function M.send(text)
    local w = m:window()
    if not w then return false, "no window" end
    m:click("input_box", w); sleep(0.25)
    w:key("ctrl+a"); w:key("BackSpace"); sleep(0.1)
    x11.paste(text); sleep(0.3)
    w:key("Return"); sleep(0.3)
    return true
end

-- 读取当前会话消息区文本（按行 y,x 排序）
function M.read()
    local boxes = m:ocr("message_area")
    table.sort(boxes, function(a, b)
        if math.abs(a.gy - b.gy) > 8 then return a.gy < b.gy end
        return a.gx < b.gx
    end)
    local lines = {}
    for _, b in ipairs(boxes) do lines[#lines + 1] = b.text end
    return lines, boxes
end

-- 当前会话标题
function M.title()
    local boxes = m:ocr("title")
    return boxes[1] and boxes[1].text or nil
end

return M
