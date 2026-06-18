-- AI 搜索 → 结果发微信文件传输助手
-- 1. 激活 Chrome → AI搜索
-- 2. OCR 读结果
-- 3. 激活微信 → 搜索文件传输助手 → 发送

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]
local cjson = require("cjson")

-------------------------------
-- 1. Chrome AI 搜索
-------------------------------
io.write("=== Chrome AI 搜索 ===\n"); io.flush()

-- 激活或启动 Chrome
os.execute("xdotool search --name Chrome windowactivate 2>/dev/null || (google-chrome &>/dev/null & sleep 2)")
ffi.C.usleep(1000000)

local WID = tonumber((io.popen("xdotool search --name Chrome 2>/dev/null | tail -1"):read("*l")))
if not WID then io.write("Chrome 启动失败\n"); os.exit(1) end

-- 获取窗口坐标
local g = io.popen("xdotool getwindowgeometry " .. WID .. " 2>/dev/null"):read("*a")
local wx = tonumber(g:match("Position: (%d+)"))
local wy = tonumber(g:match(",(%d+)"))
local ww = tonumber(g:match("Geometry: (%d+)"))
local wh = tonumber(g:match("x(%d+)"))

-- 新标签
os.execute("xdotool windowactivate " .. WID .. " 2>/dev/null")
ffi.C.usleep(300000)
os.execute("xdotool key --window " .. WID .. " ctrl+t 2>/dev/null")
ffi.C.usleep(500000)

-- 粘贴问题
local f = io.open("/tmp/_q.txt", "w"); f:write("马斯克最新身价多少"); f:close()
os.execute("xclip -selection clipboard < /tmp/_q.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key --window " .. WID .. " ctrl+v 2>/dev/null")
ffi.C.usleep(300000)

-- Tab → 回车
os.execute("xdotool key --window " .. WID .. " Tab 2>/dev/null")
ffi.C.usleep(50000)
os.execute("xdotool key --window " .. WID .. " Return 2>/dev/null")
ffi.C.usleep(3000000)

-- 截图
os.execute(string.format("import -window root -crop %dx%d+%d+%d /tmp/ai_res.png 2>/dev/null", ww, wh, wx, wy))
io.write("搜索完成\n"); io.flush()

-------------------------------
-- 2. OCR 读结果
-------------------------------
io.write("=== OCR 读取回答 ===\n"); io.flush()
local lib = ffi.load("libwechat_ocr_core.so")
ffi.cdef[[
    typedef struct ocr_engine_t ocr_engine_t;
    ocr_engine_t* ocr_create(const char*,const char*,const char*);
    char* ocr_capture_file(ocr_engine_t*, const char*, int, int);
    void ocr_free_string(char*);
    void ocr_destroy(ocr_engine_t*);
]]
local e = lib.ocr_create("/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_det_infer.onnx",
                          "/opt/my-agent/wechat-ocr/models/ch_PP-OCRv4_rec_infer.onnx",
                          "/opt/my-agent/wechat-ocr/ppocr_keys_v1.txt")
local lines = {}
local s = lib.ocr_capture_file(e, "/tmp/ai_res.png", 0, 0)
if s and s ~= ffi.NULL then
    local d = cjson.decode(ffi.string(s))
    lib.ocr_free_string(s)
    for _, b in ipairs(d.boxes or {}) do if #b.text > 2 then table.insert(lines, b.text) end end
end
lib.ocr_destroy(e)
local answer = table.concat(lines, "\n")
io.write(answer:sub(1,200) .. "\n"); io.flush()

-------------------------------
-- 3. 微信搜索 → 发送
-------------------------------
io.write("=== 微信发送 ===\n"); io.flush()

-- 激活微信
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)
local gw = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
local wwx = tonumber(gw:match("Position: (%d+)"))
local wwy = tonumber(gw:match(",(%d+)"))
local www = tonumber(gw:match("Geometry: (%d+)"))
local wwh = tonumber(gw:match("x(%d+)"))

-- 点搜索框（第二列顶部）
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wwx+180, wwy+50))
ffi.C.usleep(500000)

-- 输入"文件传输助手"
local f2 = io.open("/tmp/_wx_s.txt", "w"); f2:write("文件传输助手"); f2:close()
os.execute("xclip -selection clipboard < /tmp/_wx_s.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(1000000)

-- 回车选中第一个结果
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(1000000)

-- 粘贴 AI 回答
local f3 = io.open("/tmp/_wx_msg.txt", "w"); f3:write(answer); f3:close()
os.execute("xclip -selection clipboard < /tmp/_wx_msg.txt 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(300000)

-- 发送
os.execute("xdotool key Return 2>/dev/null")
io.write("完成！\n")
