-- Chrome AI 搜索 → 复制结果 → 输出
-- 1. 激活 Chrome → 新标签 → 输入 → Tab → 回车
-- 2. 等 AI 回答 → Ctrl+A → Ctrl+C → 读取剪贴板

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]

io.write("=== AI 搜索 ===\n"); io.flush()

-- 激活 Chrome
os.execute("xdotool search --name ' - Google Chrome' windowactivate 2>/dev/null || google-chrome &>/dev/null &")
ffi.C.usleep(1000000)

local WID = tonumber((io.popen("xdotool search --name ' - Google Chrome' 2>/dev/null | head -1"):read("*l")))
if not WID then io.write("Chrome 未找到\n"); os.exit(1) end

-- 新标签
os.execute("xdotool windowactivate " .. WID .. " 2>/dev/null")
ffi.C.usleep(300000)
os.execute("xdotool key --window " .. WID .. " ctrl+t 2>/dev/null")
ffi.C.usleep(500000)

-- 输入问题（从命令行参数读取）
local query = arg[1] or "马斯克最新身价多少"
os.execute("echo '" .. query .. "' | xclip -selection clipboard 2>/dev/null")
ffi.C.usleep(100000)
os.execute("xdotool key --window " .. WID .. " ctrl+v 2>/dev/null")
ffi.C.usleep(300000)

-- Tab → 回车
os.execute("xdotool key --window " .. WID .. " Tab 2>/dev/null")
ffi.C.usleep(50000)
os.execute("xdotool key --window " .. WID .. " Return 2>/dev/null")

-- 等 AI 回答
io.write("等待 AI 回答...\n"); io.flush()
ffi.C.usleep(4000000)

-- Ctrl+A → Ctrl+C 复制页面内容
os.execute("xdotool key --window " .. WID .. " ctrl+a 2>/dev/null")
ffi.C.usleep(200000)
os.execute("xdotool key --window " .. WID .. " ctrl+c 2>/dev/null")
ffi.C.usleep(500000)

-- 读取剪贴板
local pipe = io.popen("xclip -selection clipboard -o 2>/dev/null")
if pipe then
    local content = pipe:read("*a"); pipe:close()
    -- 从查询关键词开始截取到"个网站"
    local kw = query:sub(1, 4)
    local _, s = content:find(kw)
    local e, _ = content:find("个网站")
    if s and e then
        io.write("\n=== AI 回答 ===\n")
        io.write(content:sub(s, e))
        io.write("\n")
    else
        io.write("\n" .. content:sub(1,2000) .. "\n")
    end
end

io.write("完成\n")
