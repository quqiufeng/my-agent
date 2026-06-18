-- Google AI 模式操作
-- 1. 打开 Google → 2. 输入问题 → 3. 点 AI 模式按钮 → 4. 截图结果

local ffi = require("ffi")
ffi.cdef[[int usleep(unsigned int);]]

local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))

-- 激活 Chrome
os.execute("xdotool search --name 'Google Chrome' windowactivate --sync 2>/dev/null")
ffi.C.usleep(500000)

-- 新标签页打开 Google
os.execute("xdotool key ctrl+t 2>/dev/null")
ffi.C.usleep(500000)
os.execute("echo 'https://www.google.com' | xclip -selection clipboard 2>/dev/null")
ffi.C.usleep(200000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(200000)
os.execute("xdotool key Return 2>/dev/null")
ffi.C.usleep(3000000)

-- 点搜索框（页面中央偏上）
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + ww/2, wy + wh*2/5))
ffi.C.usleep(500000)

-- 输入问题
os.execute("echo 'chrome 有什么好玩的玩法' | xclip -selection clipboard 2>/dev/null")
ffi.C.usleep(200000)
os.execute("xdotool key ctrl+v 2>/dev/null")
ffi.C.usleep(500000)

-- 点 AI 模式按钮（在搜索框下方）
os.execute(string.format("xdotool mousemove %d %d click 1 2>/dev/null", wx + ww/2 - 100, wy + wh*2/5 + 100))
ffi.C.usleep(2000000)

-- 截图
os.execute(string.format("import -window root -crop %dx%d+%d+%d /tmp/google_ai.png 2>/dev/null", ww, wh, wx, wy))
print("结果截图: /tmp/google_ai.png")
