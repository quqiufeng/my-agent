local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]
local ocr = require("wechat_ocr")

local dir = "/opt/my-agent/wechat-ocr"

ocr.init(dir .. "/models/ch_PP-OCRv4_det_infer.onnx",
         dir .. "/models/ch_PP-OCRv4_rec_infer.onnx",
         dir .. "/ppocr_keys_v1.txt")

-- 1. 点微信图标
print("1. 点微信图标...")
ocr.open(2000)
ffi.C.usleep(1000000)

-- 2. 逐字输入并发送
local msg = "你好，自动发送测试消息"
print("2. 输入: " .. msg)
ocr.send(msg)
ffi.C.usleep(2000000)

-- 3. 读取验证
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)
print("3. 聊天内容:")
local text = ocr.capture()
if text then
    for line in text:gmatch("[^\n]+") do
        print("   " .. line)
    end
end
ocr.destroy()
print("4. 完成")
