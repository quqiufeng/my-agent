-- wechat-ocr/bridge.lua — 微信入口（常驻守护，用户白名单模式）
-- 白名单: whitelist.txt（每行一个会话名），第一个是「文件传输助手」。
-- 每 POLL 秒后台轮询（quiet：不聚焦、不激活、不点开会话）：
--   import -window 抓微信窗口(遮挡可读；最小化则跳过) → OCR 第二列 →
--   对白名单每个会话读其行预览(=最新消息)；预览以标签开头（ai / ai助手，`#` 可省）
--   且与上次不同 → 去掉标签以 [微信输入:<会话名>] 转发大脑。
-- 大脑回复经 operator/tools/wechat_send.sh --to <会话名> 发送，自动加 ai助手 前缀。
-- 用法: ./bridge.sh

package.path = "/opt/my-agent/wechat-ocr/?.lua;/opt/my-agent/wechat-ocr/lua/?.lua;"
    .. "/opt/my-agent/wechat-ocr/lua/?/init.lua;/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
    .. (package.path or "")
package.cpath = "/opt/my-agent/wechat-ocr/lib/?.so;/usr/local/lualib/?.so;;" .. (package.cpath or "")

local cjson = require("cjson")
local watcher = require("wechat_ocr.watcher")

local DIR       = os.getenv("WECHAT_DIR") or "/opt/my-agent/wechat-ocr"
local AGENT_URL = os.getenv("AGENT_URL") or "http://localhost:4097"
local SENT_LOG  = os.getenv("WECHAT_SENT_LOG") or "/tmp/myagent_wechat_sent.log"
local POLL      = tonumber(os.getenv("WECHAT_POLL_SEC") or "15")   -- 轮询间隔（秒）
local ONCE      = os.getenv("WECHAT_ONCE") == "1"                  -- 只跑一轮（调试）
local DRY       = os.getenv("WECHAT_DRY") == "1"                   -- 只打印不转发（调试）
local REPLY_WAIT = tonumber(os.getenv("WECHAT_REPLY_WAIT") or "40") -- 等大脑回复上限（秒）
local WHITELIST = os.getenv("WECHAT_WHITELIST") or (DIR .. "/whitelist.txt")
local CMD_TAG   = os.getenv("WECHAT_CMD_TAG") or "ai助手"           -- 指令标签（# 可选）

-- 取指令正文：白名单消息以标签开头（`ai`/`ai助手`，`#` 可省；手机不好打#）。
-- 容错：`#` 可能被 OCR 成「并/井」，`ai` 的 i 可能变 1/l/L。命中返回正文，否则 nil。
local function to_command(text)
    local t = text:gsub("^%s+", ""):gsub("^[#并井]%s*", "")
    -- 双字标签 ai 及其 OCR 变体（a/i/l/1 组合）
    local rest, n = t:gsub("^[Aa][Ii1lL][Ii1lL]?", "", 1)
    if n == 0 then
        -- OCR 常把 "ai" 读成单个 l / L / 1
        rest, n = t:gsub("^[lL1]", "", 1)
        if n == 0 then return nil end
    end
    if rest:match("^[A-Za-z0-9]") then return nil end   -- 排除 air/aid 等英文词
    rest = rest:gsub("^%s*助手", ""):gsub("^%s+", "")
    return (rest:gsub("%s+$", ""))
end

-- ── 白名单 ──────────────────────────────────────────────────
local function load_users()
    local users = {}
    local f = io.open(WHITELIST, "r")
    if f then
        for line in f:lines() do
            line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then users[#users + 1] = line end
        end
        f:close()
    end
    if #users == 0 then users = { "文件传输助手" } end
    return users
end

-- ── 转发大脑（/tui，实时可见、可人工介入），带来源会话名 ─────
local function tui_attached()
    return os.execute("pgrep -f 'opencode[ ]attach' >/dev/null 2>&1") == 0
end

local function forward(user, text)
    if not tui_attached() then
        io.stderr:write("[bridge] opencode TUI 未运行，自动拉起...\n")
        os.execute("/opt/my-agent/operator/ensure_tui.sh >/dev/null 2>&1")
    end
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    f:write(cjson.encode({ text = "[微信输入:" .. user .. "] " .. text }))
    f:close()
    os.execute(string.format(
        "sh -c 'curl -s --max-time 10 -X POST -H \"Content-Type: application/json\" --data-binary @%s \"%s/tui/append-prompt\" >/dev/null 2>&1; "
        .. "curl -s --max-time 10 -X POST -H \"Content-Type: application/json\" -d \"{}\" \"%s/tui/submit-prompt\" >/dev/null 2>&1; rm -f %s' >/dev/null 2>&1",
        tmp, AGENT_URL, AGENT_URL, tmp))
end

-- ── USB 音响提示音 ──────────────────────────────────────────
local NOTIFY_WAV = os.getenv("WECHAT_NOTIFY_WAV") or "/tmp/myagent_notify.wav"

local function notify()
    local f = io.open(NOTIFY_WAV, "rb")
    if f then f:close() else
        os.execute(string.format(
            "ffmpeg -y -f lavfi -i \"sine=frequency=880:duration=0.25\" "
            .. "-af volume=0.5 '%s' >/dev/null 2>&1", NOTIFY_WAV))
    end
    local sink = os.getenv("VOICE_SINK") or ""
    if sink ~= "" then
        os.execute(string.format("pw-play --target '%s' '%s' >/dev/null 2>&1 &", sink, NOTIFY_WAV))
    else
        os.execute(string.format("pw-play '%s' >/dev/null 2>&1 &", NOTIFY_WAV))
    end
end

-- ── 防自循环：大脑回程发出去的消息记在日志里 ────────────────
local function normalize(s)
    return (s:gsub("%s", ""):gsub("[%p%c]", ""))
end

-- 判断预览/正文是否是我们自己刚发过的回复（带标签/去标签都比）
local function is_self(preview, cmd)
    local cands = {}
    for _, c in ipairs({ preview or "", cmd or "" }) do
        local n = normalize(c):gsub("[%.。…]+$", "")   -- 去预览省略号
        if n ~= "" then cands[#cands + 1] = n end
    end
    if #cands == 0 then return false end
    local f = io.open(SENT_LOG, "r")
    if not f then return false end
    local self = false
    for line in f:lines() do
        if line ~= "" then
            local nl = normalize(line)
            local nb = normalize(to_command(line) or line)
            for _, c in ipairs(cands) do
                if (nl == c or nb == c)
                    or (#c >= 4 and (nl:find(c, 1, true) or c:find(nl, 1, true)
                        or nb:find(c, 1, true) or c:find(nb, 1, true))) then
                    self = true; break
                end
            end
        end
        if self then break end
    end
    f:close()
    return self
end

local function sent_lines()
    local n = 0
    local f = io.open(SENT_LOG, "r")
    if f then for _ in f:lines() do n = n + 1 end; f:close() end
    return n
end

-- ── 每个会话的上次转发（去重，持久化） ──────────────────────
local LAST_FILE = os.getenv("WECHAT_LAST_FILE") or "/tmp/myagent_wechat_last"
local last = {}
local function load_last()
    local f = io.open(LAST_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local u, t = line:match("^([^\t]+)\t(.*)$")
        if u and t and t ~= "" then last[u] = t end
    end
    f:close()
end
local function save_last()
    local f = io.open(LAST_FILE, "w")
    if f then
        for u, t in pairs(last) do f:write(u .. "\t" .. t .. "\n") end
        f:close()
    end
end

-- ── 启动 ────────────────────────────────────────────────────
local ok, err = watcher.init()
if not ok then io.stderr:write("[bridge] watcher.init 失败: " .. tostring(err) .. "\n"); os.exit(1) end

local USERS = load_users()
load_last()
io.write(string.format("[bridge] 微信白名单监控启动：每 %d 秒轮询，用户[%s]，目标 %s\n",
    POLL, table.concat(USERS, ","), AGENT_URL))
io.flush()

-- 全程后台读第二列预览：不聚焦、不激活、不点开会话（quiet）。
-- 白名单会话的预览以标签开头且与上次不同 → 作为指令转发。
-- 微信被最小化/隐藏时抓不到（保持微信未最小化即可）；遮挡不影响。

-- ── 语音消息 → 右键「语音转文字」→ OCR 识别 ──────────────────────
local OCR_TEXT = DIR .. "/ocr_text.sh"
local VPID = os.time()
local function sh_out(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return "" end
    local s = f:read("*a"); f:close(); return s or ""
end
local function is_voice(text) return text and text:find("语音") ~= nil end
-- 聊天区起始 x（与 wechat_robot.col_geometry 一致）
local function chat_x0(win)
    local scale = (win.w or 2560) / 2560
    return math.floor(75 * scale) + math.floor(445 * scale)
end
-- 聊天区里最新的「微信绿」语音气泡（窗口坐标）
local function green_bubble(shot, win)
    local cx = chat_x0(win); local cw = win.w - cx
    local info = sh_out(string.format(
        "convert '%s' -crop %dx%d+%d+0 +repage -fuzz 10%% -transparent '#95EC69' "
        .. "-alpha extract -negate -trim info:", shot, cw, win.h, cx))
    local W, H, X, Y = info:match("PNG (%d+)x(%d+) %d+x%d+%+(%d+)%+(%d+)")
    if not W then return nil end
    return { x = cx + tonumber(X), y = tonumber(Y), w = tonumber(W), h = tonumber(H) }
end
-- 点开会话 → 右键语音气泡 → 语音转文字 → 裁白底文字 OCR
local OCR_BOXES = DIR .. "/ocr_boxes.sh"
local function convert_voice(win, row)
    local shot, b
    for _ = 1, 3 do
        os.execute(string.format("xdotool mousemove %d %d click 1",
            win.x + row.x + math.floor(row.w / 2), win.y + row.y + math.floor(row.h / 2)))
        os.execute("sleep 0.8")
        for _ = 1, 4 do
            shot = watcher.window_capture()
            if shot then b = green_bubble(shot, win) end
            if b then break end
            os.execute("sleep 0.5")
        end
        if b then break end
    end
    if not b then io.write("[bridge] 未找到语音气泡\n"); return nil end
    local bx = win.x + b.x + math.floor(b.w * 0.35)
    local by = win.y + b.y + math.floor(b.h / 2)
    os.execute(string.format("xdotool mousemove %d %d click 3", bx, by))   -- 右键气泡
    os.execute("sleep 1.2")
    -- 全屏抓图，OCR 找含「转文字」的菜单项
    local mpng = string.format("/tmp/wx_menu_%d.png", VPID)
    os.execute(string.format("import -window root '%s'", mpng))
    local mx, my
    for line in sh_out(OCR_BOXES .. " '" .. mpng .. "'"):gmatch("[^\n]+") do
        local x, y, w2, h2, t = line:match("^(%d+)\t(%d+)\t(%d+)\t(%d+)\t(.+)$")
        if t and t:find("转文字") then
            mx = tonumber(x) + math.floor(tonumber(w2) / 2)
            my = tonumber(y) + math.floor(tonumber(h2) / 2)
            break
        end
    end
    os.remove(mpng)
    if mx then
        os.execute(string.format("xdotool mousemove %d %d click 1", mx, my))
        os.execute("sleep 2.5")
    else
        -- 已转换（菜单项是「收起文字」）→ 点标题栏空白关菜单（勿用 Esc，会关会话）
        os.execute(string.format("xdotool mousemove %d %d click 1", win.x + 800, win.y + 22))
        os.execute("sleep 0.4")
    end
    local shot2 = watcher.window_capture()
    if not shot2 then return nil end
    local tx = win.x + b.x - 280
    local ty = win.y + b.y + b.h + 6
    local crop = string.format("/tmp/wx_voice_%d.png", VPID)
    local outt = string.format("/tmp/wx_voicetext_%d.txt", VPID)
    os.execute(string.format(
        "convert '%s' -crop 560x150+%d+%d +repage -resize 300%% -colorspace Gray -normalize '%s'",
        shot2, tx, ty, crop))
    sh_out(OCR_TEXT .. " '" .. crop .. "' '" .. outt .. "'")
    local text = ""
    local f = io.open(outt, "r")
    if f then text = f:read("*a") or ""; f:close() end
    os.remove(crop); os.remove(outt)
    text = text:gsub("%s+", "")
    if text == "" then return nil end
    return text
end

-- ── 需要时先取消最小化再读，读完空闲则最小化 ──────────────
local function is_hidden(win)
    if not win then return false end
    local f = io.popen("xprop -id " .. win.id .. " WM_STATE 2>/dev/null")
    if not f then return false end
    local s = f:read("*a"); f:close()
    return s ~= nil and s:find("Iconic") ~= nil
end
local function wechat_attn(win)
    if not win then return false end
    local f = io.popen("xprop -id " .. win.id .. " _NET_WM_STATE 2>/dev/null")
    if not f then return false end
    local s = f:read("*a"); f:close()
    return s ~= nil and s:find("DEMANDS_ATTENTION") ~= nil
end
local function wechat_open(win)
    if not win then return end
    os.execute("xdotool windowmap " .. win.id .. " 2>/dev/null")
    os.execute("wmctrl -i -a " .. win.id .. " 2>/dev/null")
    os.execute("sleep 0.7")
end
local function wechat_background(win)
    if not win then return end
    os.execute("xdotool windowminimize " .. win.id .. " 2>/dev/null")
end

while true do
    local win = watcher.window()
    local hidden = win and is_hidden(win)
    local attn = win and wechat_attn(win)
    if hidden and not attn then
        io.write("[bridge] 空闲（无新消息），不打扰\n")
    else
    if hidden then wechat_open(win) end
    local shot, w = watcher.window_capture()
    if not shot then
        io.write("[bridge] 微信不可见，跳过\n")
    else
        local res = watcher.ocr(shot, win)
        local has_cmd = false
        for _, user in ipairs(USERS) do
            local row = res and watcher.find_row(res, user)
            if row then
                local text = watcher.read_preview(shot, win, row)
                -- 标签可选：能识别就剥离，否则整条当指令（白名单会话专用；靠 is_self 防回环）
                local cmd = text and (to_command(text) or text) or nil
                if text and text ~= "" and text ~= last[user] and is_voice(text) then
                    -- 语音消息：转文字 → 转发
                    has_cmd = true
                    last[user] = text; save_last()
                    io.write("[bridge] 语音消息 → 转文字(" .. user .. ")\n"); io.flush()
                    local vtext = convert_voice(win, row)
                    if vtext and vtext ~= "" then
                        io.write("[微信语音:" .. user .. "] " .. vtext .. "\n"); io.flush()
                        if not DRY then
                            notify()
                            local before = sent_lines()
                            forward(user, vtext)
                            for _ = 1, REPLY_WAIT do
                                if sent_lines() > before then break end
                                os.execute("sleep 1")
                            end
                            os.execute("sleep 4")
                            wechat_background(win)   -- 执行完最小化回后台
                        end
                    else
                        io.write("[bridge] 语音转文字为空\n")
                    end
                elseif text and text ~= "" and text ~= last[user] and cmd and cmd ~= "" then
                    has_cmd = true
                    if is_self(text, cmd) then
                        io.write("[bridge] 跳过(自己发的): " .. text .. "\n")
                        last[user] = text; save_last()
                    elseif DRY then
                        io.write("[bridge][DRY] 将转发 -> " .. user .. ": " .. cmd .. "\n")
                        last[user] = text; save_last()
                    else
                        io.write("[微信输入:" .. user .. "] " .. cmd .. "\n")
                        io.flush()
                        notify()                          -- USB 音响提示音
                        local before = sent_lines()
                        forward(user, cmd)
                        last[user] = text; save_last()
                        for _ = 1, REPLY_WAIT do
                            if sent_lines() > before then break end
                            os.execute("sleep 1")
                        end
                        os.execute("sleep 4")
                        wechat_background(win)   -- 执行完最小化回后台
                    end
                end
            end
        end
        if not has_cmd then
            io.write("[bridge] 无新指令\n")
            wechat_background(win)
        end
    end
    end
    io.flush()
    if ONCE then break end
    os.execute("sleep " .. POLL)
end

watcher.close()
