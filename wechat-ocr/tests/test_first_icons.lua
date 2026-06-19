#!/usr/bin/env luajit
-- ============================================================
-- WeChat OCR - 第一列小图标检测
-- ============================================================
-- 功能: 截图微信窗口 → 检测第一列（图标列）的小图标
--
-- 一键测试命令:
--   cd /opt/my-agent/wechat-ocr && \
--   export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib && \
--   export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;" && \
--   export LUA_CPATH="/usr/local/lualib/?.so;;" && \
--   luajit tests/test_first_icons.lua
--
-- ============================================================
-- 算法说明:
--   第一列（图标列）宽度固定 75px，包含聊天/通讯录/收藏等7个图标
--   用 C++ OCR 引擎确认窗口位置后，框选第一列区域
--   Python CV 做多阈值二值化 + 文字行过滤检测图标
--   输出 ~/wechat_first_icons_YYYYMMDD_HHMMSS.png
-- ============================================================

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

io.write("=== 第一列小图标检测 ===\n\n"); io.flush()

-- 1. 激活微信
io.write("[1/3] 激活微信...\n"); io.flush()
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

-- 2. 获取窗口几何
local geo = io.popen("xdotool getactivewindow getwindowgeometry 2>/dev/null"):read("*a")
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))
if not wx then io.write("❌ 获取窗口失败\n"); os.exit(1) end
io.write(string.format("  窗口: (%d,%d) %dx%d\n\n", wx, wy, ww, wh)); io.flush()

-- 3. Python 检测第一列图标
io.write("[2/3] 检测第一列图标...\n"); io.flush()
local ts = os.date("%Y%m%d_%H%M%S")
local outfile = os.getenv("HOME") .. "/wechat_first_icons_" .. ts .. ".png"
local cmd = string.format(
    "/data/venv/bin/python3 tests/find_first_icons.py %d %d %d %d '%s' 2>/dev/null",
    wx, wy, ww, wh, outfile)
os.execute(cmd)

-- 4. 隐藏微信
io.write("[3/3] 隐藏微信...\n"); io.flush()
os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
io.write("  微信已隐藏\n")
