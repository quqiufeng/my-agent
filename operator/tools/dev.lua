local DIR = (arg[0] or ""):match("^(.*)/") or "."
local REPO = "/opt/my-agent"
local OP = REPO .. "/operator"
local TOOLS = OP .. "/tools"

local function q(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function gcommit(msg)
    os.execute("git -C " .. q(REPO) .. " add -A >/dev/null 2>&1")
    local rc = os.execute("git -C " .. q(REPO) ..
        " -c user.name=myagent -c user.email=myagent@local commit -m " .. q(msg) ..
        " >/dev/null 2>&1")
    print(rc == 0 and ("已提交: " .. msg) or "(无改动可提交)")
end

local info = [[
# my-agent 结构与自我扩展规范

## 是什么
入口(语音/微信/定时，只产文本) → opencode 大脑 → 白名单工具 operator/tools/*.sh → 本机操作。
已有能力清单见 operator/CAPABILITIES.md（`tools/dev.sh caps`）。

## 自我扩展：Lua 做本机，JS 做浏览器
现有能力不够时，新增工具：
- **Lua**：本机/系统/音视频/文件/终端/窗口（`xdo.lua`）；
- **JS**：浏览器网页能力，统一走 `agentkit.cdp` / `cdp.js` / `cdpd.js`（CDP/DOM）；
- `operator/tools/<name>.sh` 只做几行兼容入口（exec luajit/node）+ 元数据，供 `TOOLS.md` 发现；
- 不把浏览器逻辑写成 Lua+curl/xdo，也不把业务逻辑写进 shell。

## 目录
operator/tools/          白名单工具（入口 .sh + 逻辑 .lua/.js）
operator/CAPABILITIES.md 能力清单
operator/TOOLS.md        工具表（由 plugin.sh index 生成）
operator/plugin.sh       `plugin.sh index` 重建 TOOLS.md
operator/opencode.json   权限（bash 仅 tools/*）
agentkit/                统一库：窗口/OCR/输入/CDP/语音
agentkit/tools/*.js      CDP 桥（cdp.js/cdpd.js/gemini.js）
operator/report/         Kami 排版 HTML→PNG/PDF（render.sh）

## 开发一个新能力
1. `tools/dev.sh new <name>` 生成 `<name>.js` + `<name>.sh` 入口
2. 填 JS 逻辑（浏览器统一走 `agentkit.cdp`/`cdp.js`）
3. `tools/dev.sh commit "feat(tool): <name> ..."`
4. `tools/dev.sh index` → `tools/dev.sh restart`

## 常用积木
- 网页：固定端口 Chrome（chrome_debug.sh）+ `ak.cdp`；cookie+curl：cookie.sh/fetch.sh
- 出图：operator/report/render.sh in.html out.png（Kami）
- 发微信：tools/wechat_send.sh / wechat_send_file.sh
- 语音：ak.voice（tts/asr）
]]

local function new_tool(name)
    if not name or name == "" then
        io.stderr:write("用法: dev.sh new <name>\n")
        os.exit(2)
    end
    local sh = TOOLS .. "/" .. name .. ".sh"
    local js = TOOLS .. "/" .. name .. ".js"
    if read_file(sh) or read_file(js) then
        io.stderr:write("已存在: " .. (read_file(sh) and sh or js) .. "\n")
        os.exit(1)
    end

    local jf = assert(io.open(js, "w"))
    jf:write([[#!/usr/bin/env node
const { execFileSync } = require('child_process');
const CDP = '/opt/my-agent/agentkit/tools/cdp.js';
const cdp = (cmd, arg) => execFileSync('node', [CDP, cmd, arg || ''], { encoding: 'utf8' });
(async () => {
  cdp('goto', 'https://example.com');
  await new Promise(r => setTimeout(r, 2000));
  console.log(cdp('eval', 'document.body.innerText.slice(0,500)'));
})();
]])
    jf:close()

    local sf = assert(io.open(sh, "w"))
    sf:write("#!/usr/bin/env bash\n")
    sf:write("# tools/" .. name .. ".sh — 一句话说明（JS + CDP 实现）\n")
    sf:write("# @desc <用途：通过专用 Chrome + CDP/DOM 从网页获取/操作>\n")
    sf:write("# @usage tools/" .. name .. ".sh <参数>\n")
    sf:write("# @rule 说“<触发词>” → 用 `tools/" .. name .. ".sh`\n")
    sf:write("# @order 50\n")
    sf:write("set -uo pipefail\n")
    sf:write("DIR=\"$(cd \"$(dirname \"$0\")\" && pwd)\"\n")
    sf:write("ss -ltn 2>/dev/null | grep -q ':9222 ' || \"$DIR/chrome_debug.sh\" >/dev/null 2>&1\n")
    sf:write("exec node \"$DIR/" .. name .. ".js\" \"$@\"\n")
    sf:close()

    os.execute("chmod 755 " .. q(sh) .. " " .. q(js))
    print("已创建: " .. sh .. " + " .. js)
    gcommit("feat(tool): scaffold " .. name)
end

local cmd = arg[1] or "info"

if cmd == "info" then
    print(info)
elseif cmd == "caps" then
    local s = read_file(OP .. "/CAPABILITIES.md")
    if s then io.write(s) else io.stderr:write("缺少 CAPABILITIES.md\n"); os.exit(1) end
elseif cmd == "list" then
    local p = io.popen("ls -1 " .. q(TOOLS) .. "/*.sh 2>/dev/null | sed 's#.*/##' | sort")
    if p then io.write(p:read("*a") or ""); p:close() end
elseif cmd == "new" then
    new_tool(arg[2])
elseif cmd == "index" then
    os.execute(q(OP .. "/plugin.sh") .. " index")
    gcommit("chore(tools): regenerate TOOLS.md")
elseif cmd == "commit" then
    gcommit(arg[2] or "chore(dev): update")
elseif cmd == "push" then
    os.execute("git -C " .. q(REPO) .. " push origin HEAD")
elseif cmd == "restart" then
    os.execute(q(OP .. "/start.sh"))
else
    io.stderr:write("用法: dev.sh info | caps | list | new <name> | index | commit [msg] | push | restart\n")
    os.exit(2)
end
