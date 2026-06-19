#!/usr/bin/env luajit
-- news_execute.lua — 检测文件传输助手是否有未读消息
-- 复用 badge_detect.lua 检测逻辑

local badge = require("wechat_ocr.badge_detect")

io.write("检测中...\n"); io.flush()

local result = badge.detect()
if not result then
    io.write("检测失败: " .. tostring(tonumber) .. "\n")
    os.exit(1)
end

local ft_entry = badge.find_file_transfer(result)
if not ft_entry then
    io.write("未找到文件传输助手\n")
    os.exit(0)
end

if ft_entry.found then
    io.write("文件传输助手有未读消息\n")
else
    io.write("文件传输助手无未读消息\n")
end
