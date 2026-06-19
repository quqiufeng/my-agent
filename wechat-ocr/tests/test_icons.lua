#!/usr/bin/env luajit
-- ============================================================
-- WeChat OCR - 全窗口小图标检测
-- ============================================================
-- 功能: 激活微信 → 截图 → Python CV分析 → 标注所有小图标
--
-- 一键测试命令:
--   cd /opt/my-agent/wechat-ocr && \
--   export LD_LIBRARY_PATH=./lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib && \
--   export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;" && \
--   export LUA_CPATH="/usr/local/lualib/?.so;;" && \
--   luajit tests/test_icons.lua
--
-- ============================================================
-- 图标检测算法（Python find_icons.py 中实现）
-- ============================================================
-- 输入：微信窗口截图
--
-- 步骤:
--   1) 多阈值二值化（180→5, 步长-5）
--      从深色到浅色逐层降低阈值，捕捉黑色文字到灰色图标
--
--   2) 轮廓查找 + 基础过滤
--      - 最小尺寸: 6×6px
--      - 宽高比: 0.35~2.2（近似方形）
--      - 面积: 36~4000px²
--
--   3) 文字行过滤（关键：区分文字与图标）
--      文字特征：同一水平线上多个blob密集排列（间距<45px）
--      图标特征：独立分布或间距较疏（>45px）
--      判据：同一Y（±15px）内，水平间距<45px的邻居≥4个 → 判为文字行
--
--   4) 去重 + 标注输出
--      按 8px 网格去重，绿色框标注并编号
--
-- 输出: ~/wechat_icons_YYYYMMDD_HHMMSS.png
-- ============================================================

package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]

os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)

local geo = io.popen("xdotool getactivewindow getwindowgeometry"):read("*a")
local wx = tonumber(geo:match("Position: (%d+)"))
local wy = tonumber(geo:match(",(%d+)"))
local ww = tonumber(geo:match("Geometry: (%d+)"))
local wh = tonumber(geo:match("x(%d+)"))

io.write(string.format("窗口: (%d,%d) %dx%d\n", wx, wy, ww, wh))
local ts = os.date("%Y%m%d_%H%M%S")
local outfile = os.getenv("HOME") .. "/wechat_icons_" .. ts .. ".png"
local cmd = string.format("/data/venv/bin/python3 tests/find_icons.py %d %d %d %d '%s' 2>/dev/null", wx, wy, ww, wh, outfile)
os.execute(cmd)

-- 隐藏微信窗口
os.execute("xdotool search --name 微信 windowminimize 2>/dev/null")
io.write("  微信已隐藏\n")
