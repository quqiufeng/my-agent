-- 打开 Chrome → 新标签 → 地址栏输入 → Tab → 回车（AI 搜索）
os.execute("google-chrome &>/dev/null &")

-- 等 Chrome 启动
local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]
ffi.C.usleep(1000000)

-- 找 Chrome 窗口
local wid = tonumber((io.popen("xdotool search --name Chrome 2>/dev/null | tail -1"):read("*l")))

-- 新标签
os.execute("xdotool key --window " .. wid .. " ctrl+t &>/dev/null &")
ffi.C.usleep(300000)

-- 剪贴板输入中文
local f = io.open("/tmp/_chrome_q.txt", "w")
f:write("马斯克最新身价多少")
f:close()
os.execute("xclip -selection clipboard < /tmp/_chrome_q.txt &>/dev/null &")
ffi.C.usleep(200000)

-- 粘贴 + Tab + 回车
os.execute("xdotool key --window " .. wid .. " ctrl+v &>/dev/null &")
ffi.C.usleep(200000)
os.execute("xdotool key --window " .. wid .. " Tab Return &>/dev/null &")

print("搜索完成")
