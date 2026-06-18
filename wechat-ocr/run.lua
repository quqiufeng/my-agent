-- WeChat OCR - 启动入口
-- 环境要求:
--   luajit + libwechat_ocr_core.so + ONNX Runtime GPU
-- 用法:
--   luajit run.lua                  -- 单次捕捉聊天内容
--   luajit run.lua send "你好"      -- 发送消息
--   luajit run.lua monitor          -- 持续监控新消息

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

local ocr = require("wechat_ocr")
local dir = arg[0]:match("(.*/)") or "."

local det  = dir .. "models/ch_PP-OCRv4_det_infer.onnx"
local rec  = dir .. "models/ch_PP-OCRv4_rec_infer.onnx"
local dict = dir .. "ppocr_keys_v1.txt"

ocr.init(det, rec, dict)

local cmd = arg[1]
if cmd == "send" then
    local msg = arg[2] or "你好"
    ocr.send(msg)
    io.write("已发送: " .. msg .. "\n")
elseif cmd == "monitor" then
    ocr.monitor()
else
    -- 默认: 激活微信 → 捕捉内容
    os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
    ffi.C.usleep(500000)
    io.write(ocr.capture() or "(空)\n")
end
ocr.destroy()
