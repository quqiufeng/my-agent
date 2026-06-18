#!/usr/bin/env luajit
-- WeChat OCR Monitor - entry point
-- Usage: luajit run.lua
package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local ocr = require("wechat_ocr")

io.write("=== WeChat OCR Monitor ===\n")
io.write("Library loaded. Starting...\n\n")
io.flush()

ocr.start("/opt/my-agent/wechat-ocr/")
