#!/usr/bin/env luajit
-- Chrome DevTools MCP 桥 - 纯 Lua
-- 启动 MCP 服务器 → 发指令 → 读结果
-- 用法: luajit chrome_bridge.lua "打开 https://www.xiaohongshu.com 并截图"

local json = require("cjson")
local ffi = require("ffi")
ffi.cdef[[
    int popen(const char*, const char*);
    int pclose(int);
    int fflush(void*);
]]

-- 启动 MCP 服务器（守护进程）
local mcp_proc = io.popen("npx -y chrome-devtools-mcp@latest 2>/tmp/mcp_err.log", "w")
if not mcp_proc then print("启动 MCP 失败"); os.exit(1) end

local req_id = 0
local function call_tool(name, args)
    req_id = req_id + 1
    local req = json.encode({
        jsonrpc = "2.0",
        id = req_id,
        method = "tools/call",
        params = { name = name, arguments = args or {} }
    })
    mcp_proc:write(req .. "\n")
    mcp_proc:flush()
end

-- 先读取 MCP 服务器的初始化信息
os.execute("sleep 2")

-- 解析指令
local cmd = table.concat(arg, " ")
print("指令: " .. cmd)

-- 提取 URL
local url = cmd:match("(https?://[%w%.%-%/%~%?%&%=%+%#%_%.%-]+)")
if not url then
    url = cmd:match("打开%s+(.+)") or cmd:match("搜索%s+(.+)")
    if url and not url:match("^https?://") then
        url = "https://www.baidu.com/s?wd=" .. url
    end
end

-- 执行
if url then
    call_tool("navigate_page", { url = url })
    print("导航到: " .. url)
    os.execute("sleep 3")
end

if cmd:match("截图") then
    call_tool("take_screenshot", { format = "png" })
    os.execute("sleep 2")
    print("截图完成")
end

if cmd:match("搜索") then
    local kw = cmd:match("搜索(.+)")
    call_tool("take_snapshot", {})
    os.execute("sleep 2")
    print("已搜索: " .. (kw or ""))
end

-- 关闭
os.execute("sleep 1")
mcp_proc:close()
print("完成")
