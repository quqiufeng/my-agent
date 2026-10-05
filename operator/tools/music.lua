-- operator/tools/music.lua — WebDAV 无损音乐：搜索 / 播放(歌手或歌名) / 随机 / 停止 / 音量
-- 由 tools/music.sh 调用（luajit）。播放走本机 VLC → 默认输出（USB 音响）。
-- 凭据来自环境变量 WEBDAV_URL / WEBDAV_USER / WEBDAV_PASS / WEBDAV_MUSIC（由 music.sh 从 ~/.env 载入）。

local URL   = (os.getenv("WEBDAV_URL") or ""):gsub("/+$", "")
local USER  = os.getenv("WEBDAV_USER") or ""
local PASS  = os.getenv("WEBDAV_PASS") or ""
local MUSIC = os.getenv("WEBDAV_MUSIC") or ""
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
        "curl -sS -m 25 -u \"$WEBDAV_USER:$WEBDAV_PASS\" -X PROPFIND -H 'Depth: 1' '%s%s/' 2>/dev/null",
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
    os.execute("pkill -x vlc 2>/dev/null")   -- VLC 运行进程名是 vlc（cvlc 只是启动方式）
    os.remove(PIDF)
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
    if #hits == 0 then print("没有找到包含「" .. kw .. "」的歌"); os.exit(1) end
    play_list(hits)

elseif mode == "random" then
    local ts = list_tracks()
    if #ts == 0 then print("音乐库为空或不可访问"); os.exit(1) end
    play_list({ ts[math.random(#ts)] })

elseif mode == "stop" then
    stop(); print("已停止播放")

elseif mode == "volup" then
    volume("up")
elseif mode == "voldown" then
    volume("down")
elseif mode == "volume" then
    volume(arg[2])

else
    print("用法: music.sh search <关键词> | play <歌手或歌名> | random | stop | volup | voldown | volume <0-100>")
end
