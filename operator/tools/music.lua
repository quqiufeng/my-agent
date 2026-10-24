-- operator/tools/music.lua — WebDAV 无损音乐：搜索 / 播放(歌手或歌名) / 随机 / 停止 / 音量
-- 由 tools/music.sh 调用（luajit）。播放走本机 VLC → 默认输出（USB 音响）。
-- 凭据来自 ~/.env 的 WEBDAV_URL / WEBDAV_USER / WEBDAV_PASS / WEBDAV_MUSIC。

local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
require("dotenv").load()

local URL   = (os.getenv("WEBDAV_URL") or ""):gsub("/+$", "")
local USER  = os.getenv("WEBDAV_USER") or ""
local PASS  = os.getenv("WEBDAV_PASS") or ""
local MUSIC = os.getenv("WEBDAV_MUSIC") or ""
local cjson = require("cjson")
local PIDF  = "/tmp/myagent_music.pid"
local LOGF  = "/tmp/myagent_music.log"

local function urlencode(s)
    return (s:gsub("[^%w%-%._~/]", function(c) return string.format("%%%02X", string.byte(c)) end))
end
local function urldecode(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
local function read_file(p) local f = io.open(p); if not f then return nil end local s = f:read("*a"); f:close(); return s end
local function write_file(p, s) local f = io.open(p, "w"); if f then f:write(s); f:close() end end
local function shq(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

-- 列出音乐目录下的音频文件（href 原样 + 解码名）
local function list_tracks()
    if URL == "" or MUSIC == "" then return {} end
    local cmd = string.format(
        "curl -sS -m 25 --netrc-file \"$HOME/.webdav_netrc\" -X PROPFIND -H 'Depth: 1' '%s%s/' 2>/dev/null",
        URL, urlencode(MUSIC))
    local p = io.popen(cmd)
    if not p then return {} end
    local xml = p:read("*a"); p:close()
    local tracks = {}
    for href in xml:gmatch("<[Dd]:href>([^<]+)</[Dd]:href>") do
        if href:sub(-1) ~= "/" then
            local raw = href:match("([^/]+)$")
            local name = urldecode(raw)
            if name:match("%.flac$") or name:match("%.wma$") or name:match("%.mp3$")
                or name:match("%.m4a$") or name:match("%.ape$") or name:match("%.wav$") then
                tracks[#tracks + 1] = { href = href, name = name }
            end
        end
    end
    return tracks
end

local function stop()
    local pid = read_file(PIDF)
    if pid then
        local n = pid:match("%d+")
        if n then os.execute("kill " .. n .. " 2>/dev/null") end
    end
    os.execute("pkill -CONT -x vlc 2>/dev/null; pkill -KILL -x vlc 2>/dev/null")
    os.remove(PIDF)
end

-- ── 在线无损（flac.music.hi.cn，免浏览器）──────────────────────
local API = "https://flac.music.hi.cn/ajax.php"
local function gbk_pct(s)
    local p = io.popen("printf '%s' " .. shq(s) .. " | iconv -f utf-8 -t gbk 2>/dev/null | od -An -tx1 | tr -d ' \\n'")
    if not p then return "" end
    local hex = p:read("*a"); p:close()
    return (hex:gsub("(%x%x)", "%%%1"))
end
local function api_post(act, body)
    local p = io.popen(string.format(
        "curl -sS -m 25 '%s?act=%s' -H 'Content-Type: application/x-www-form-urlencoded;charset=UTF-8' -H 'Referer: https://flac.music.hi.cn/' -A 'Mozilla/5.0' --data %s",
        API, act, shq(body)))
    if not p then return nil end
    local o = p:read("*a"); p:close(); return o
end
local function online_search(kw, plat)
    plat = plat or "kuwo"
    local body = "type=search&keyword=" .. urlencode(kw) .. "&id=&platform=" .. plat
    local ok, res = pcall(cjson.decode, api_post("search", body) or "")
    return (ok and res and res.data and res.data.list) or {}
end
local function online_url(song, fmt, br)
    local body = string.format("platform=%s&songid=%s&format=%s&bitrate=%s&time=%s&sign=%s",
        song.platform or _G._onplat or "kuwo", song.id, fmt or "flac", br or "2000", song.time or 0, song.sign or "")
    local ok, res = pcall(cjson.decode, api_post("getUrl", body) or "")
    return (ok and res and res.data and res.data.url) or nil
end
-- 播放单个流（VLC，复用 stop/pid）
local function play_stream(url, label)
    if not url or url == "" then return false end
    stop()
    local cmd = string.format("setsid cvlc --intf dummy --no-video %s </dev/null >%s 2>&1 & echo $!", shq(url), LOGF)
    local p = io.popen(cmd); local pid = p and p:read("*a"):match("%d+") or nil; if p then p:close() end
    if pid then write_file(PIDF, pid) end
    write_file("/tmp/myagent_music_now", label or "")
    print("正在播放（在线·无损优先）: " .. (label or url))
    return true
end
-- 同时把流下载并上传保存到 NAS（WebDAV）
local function save_to_nas(url, title)
    if URL == "" or MUSIC == "" or not url or url == "" then return end
    local fn = (title or "song"):gsub("[\\/:?*\"<>|]", "_"):gsub("%s+", " ")
    fn = fn:sub(1, 120) .. ".flac"
    local tmp = "/tmp/myagent_dl_" .. os.time() .. ".flac"
    local cmd = string.format(
        "setsid sh -c 'curl -sL -m 300 -A \"Mozilla/5.0\" -o %s %s && curl -s -m 120 --netrc-file \"$HOME/.webdav_netrc\" -T %s \"%s%s/%s\" && rm -f %s' </dev/null >/dev/null 2>&1 &",
        shq(tmp), shq(url), shq(tmp), URL, urlencode(MUSIC), urlencode(fn), shq(tmp))
    os.execute(cmd)
    print("已在后台保存到 NAS: " .. fn)
end

-- 在线播一首：搜关键词 → 取 FLAC（失败退 320k mp3）→ VLC
local function play_online(kw, plat)
    local list = online_search(kw, plat)
    if #list == 0 then print("在线没有找到: " .. kw); return false end
    -- 选“正常标题”：精确 > 含关键词；排除 变速/cover/翻唱/remix/DJ/伴奏/纯音乐/现场 等；有 flac 加分
    local function score(sn)
        local n = sn.name or ""; local l = n:lower(); local sc = 0
        if n == kw then sc = sc + 100
        elseif l:find(kw:lower(), 1, true) then sc = sc + 50
        else sc = sc - 30 end
        for _, bad in ipairs({ "变速", "cover", "翻唱", "remix", "伴奏", "纯音乐", "现场", "live", "dj", "加速", "慢速", "盘点", "合集", "完整版", "女声", "男声", "钢琴", "吉他" }) do
            if l:find(bad, 1, true) then sc = sc - 80 end
        end
        for _, q in ipairs(sn.minfo or {}) do if q.format == "flac" then sc = sc + 10 end end
        return sc
    end
    local pick, best = list[1], -1e9
    for _, sn in ipairs(list) do local sc = score(sn); if sc > best then best, pick = sc, sn end end
    _G._onplat = plat or "kuwo"
    local url = online_url(pick, "flac", "2000") or online_url(pick, "mp3", "320")
    if not url then print("取直链失败"); return false end
    local label = (pick.name or "") .. " - " .. (pick.artist or "")
    play_stream(url, label)
    save_to_nas(url, label)
    return true
end

-- 播放一组曲目（VLC 播放列表）
local function play_list(tracks)
    if #tracks == 0 then return end
    stop()
    local cred = urlencode(USER) .. ":" .. urlencode(PASS)
    local host = URL:gsub("^https?://", "")
    local urls = {}
    for _, t in ipairs(tracks) do
        urls[#urls + 1] = shq("http://" .. cred .. "@" .. host .. t.href)
    end
    local cmd = string.format(
        "setsid cvlc --intf dummy --no-video %s </dev/null >%s 2>&1 & echo $!",
        table.concat(urls, " "), LOGF)
    local p = io.popen(cmd)
    local pid = p and p:read("*a"):match("%d+") or nil
    if p then p:close() end
    if pid then write_file(PIDF, pid) end
    write_file("/tmp/myagent_music_now", tracks[1].name)
    if #tracks == 1 then
        print("正在播放: " .. tracks[1].name)
    else
        print(string.format("正在播放 %d 首（播放列表），首曲: %s", #tracks, tracks[1].name))
    end
end

local function filter_tracks(kw)
    local hits = {}
    for _, t in ipairs(list_tracks()) do
        if kw == "" or t.name:find(kw, 1, true) then hits[#hits + 1] = t end
    end
    return hits
end

-- 音量：控制默认输出 sink（PipeWire/wpctl）
local function volume(arg1)
    if arg1 == "up" then
        os.execute("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ 2>/dev/null")
    elseif arg1 == "down" then
        os.execute("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- 2>/dev/null")
    elseif arg1 then
        local n = tonumber((arg1:gsub("%%", "")))
        if n then os.execute(string.format("wpctl set-volume @DEFAULT_AUDIO_SINK@ %.2f 2>/dev/null", n / 100)) end
    end
    local p = io.popen("wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null")
    local out = p and p:read("*a") or ""
    if p then p:close() end
    local vol = out:match("([%d%.]+)")
    if vol then print(string.format("音量: %d%%%s", math.floor(tonumber(vol) * 100 + 0.5),
        out:find("MUTED") and "（静音）" or ""))
    else
        print("音量已调整")
    end
end

local mode = arg[1] or "help"

if mode == "search" then
    local kw = arg[2] or ""
    local hits = filter_tracks(kw)
    if #hits == 0 then print("没有匹配: " .. kw); os.exit(1) end
    for i, t in ipairs(hits) do print(string.format("%d. %s", i, t.name)) end

elseif mode == "play" then
    local kw = arg[2] or ""
    if kw == "" then print("用法: music.sh play <歌手或歌名>"); os.exit(2) end
    local hits = filter_tracks(kw)
    if #hits > 0 then play_list(hits)
    else play_online(kw, arg[3] or "kuwo") end

elseif mode == "online" then
    local kw = arg[2] or ""; if kw == "" then print("用法: music.sh online <关键词> [kuwo|wyy]"); os.exit(2) end
    play_online(kw, arg[3] or "kuwo")

elseif mode == "random" then
    local ts = list_tracks()
    if #ts == 0 then print("音乐库为空或不可访问"); os.exit(1) end
    play_list({ ts[math.random(#ts)] })

elseif mode == "next" then
    local ts = list_tracks()
    if #ts == 0 then print("音乐库为空或不可访问"); os.exit(1) end
    local cur = read_file("/tmp/myagent_music_now")
    local pick
    for _ = 1, 12 do
        pick = ts[math.random(#ts)]
        if not cur or pick.name ~= cur then break end
    end
    play_list({ pick })

elseif mode == "stop" then
    stop(); print("已停止播放")

elseif mode == "volup" then
    volume("up")
elseif mode == "voldown" then
    volume("down")
elseif mode == "volume" then
    volume(arg[2])

else
    print("用法: music.sh search <关键词> | play <歌手或歌名>(本地,无则在线) | online <关键词> [kuwo|wyy] | random | next | stop | volup | voldown | volume <0-100>")
end
