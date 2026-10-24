local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ROOT = DIR .. "/../.."
package.path = DIR .. "/?.lua;" .. ROOT .. "/voice/?.lua;" .. package.path
local vcfg = require("config")

local ffi = require("ffi")
ffi.cdef[[
int open(const char *pathname, int flags, ...);
int flock(int fd, int operation);
]]

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function dq(s)
    return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("%$", "\\$"):gsub("`", "\\`") .. '"'
end

local function size(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local n = f:seek("end") or 0
    f:close()
    return n
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function capture(cmd)
    local p = io.popen(cmd .. " 2>/dev/null")
    local s = p and (p:read("*a") or "") or ""
    if p then p:close() end
    return s
end

local function chars(s)
    local t = {}
    for c in tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = c end
    return t
end

local function clean_punct(s)
    return (tostring(s):gsub("[，。！？、；：·,.!?;:…—－（）()【】「」『』《》〈〉“”‘’\"' 　]", ""))
end

local function wrap_text(s, n)
    n = n or 12
    local c = chars(clean_punct(s))
    local out = {}
    for i = 1, #c, n do out[#out + 1] = table.concat(c, "", i, math.min(i + n - 1, #c)) end
    return table.concat(out, "\\N")
end

local function duration(path)
    local s = capture("ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " .. q(path))
    return tonumber(s:match("([%d%.]+)")) or 0
end

local function timecode(t)
    return string.format("0:%02d:%05.2f", math.floor(t / 60), t % 60)
end

local FONT_STYLE = "Default,Noto Sans CJK SC Bold,14,&H00FFCC66,&H00FFCC66,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,1,0,2,10,10,24,1"
local PAUSE, INTRO = 0.3, 0.3

local VIDEO, TEXT, REF = nil, nil, ""
local VOICE = os.getenv("VDUB_VOICE") or "话术"
local OUT, TO = nil, ""
local NOSEND, KEEPAUDIO, FG = true, false, false
local SPEED = tonumber(os.getenv("VDUB_SPEED")) or 0.85
local PROBE, FIT = false, false
local CLONE_SPEED = tonumber(os.getenv("VDUB_CLONE_SPEED")) or 1.0
local SS, ET = 0, 0

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--ref" then REF = arg[i + 1] or ""; i = i + 2
    elseif a == "--voice" then VOICE = arg[i + 1] or ""; i = i + 2
    elseif a == "--speed" then SPEED = tonumber(arg[i + 1]) or SPEED; i = i + 2
    elseif a == "--clone-speed" then CLONE_SPEED = tonumber(arg[i + 1]) or CLONE_SPEED; i = i + 2
    elseif a == "--ss" then SS = tonumber(arg[i + 1]) or 0; i = i + 2
    elseif a == "--trim-end" then ET = tonumber(arg[i + 1]) or 0; i = i + 2
    elseif a == "--probe" then PROBE = true; i = i + 1
    elseif a == "--fit" then FIT = true; i = i + 1
    elseif a == "--out" then OUT = arg[i + 1]; i = i + 2
    elseif a == "--to" then TO = arg[i + 1] or ""; NOSEND = false; i = i + 2
    elseif a == "--send" then NOSEND = false; i = i + 1
    elseif a == "--no-send" then NOSEND = true; i = i + 1
    elseif a == "--keep-audio" then KEEPAUDIO = true; i = i + 1
    elseif a == "--fg" then FG = true; i = i + 1
    else
        if not VIDEO then VIDEO = a elseif not TEXT then TEXT = a end
        i = i + 1
    end
end

if not VIDEO or VIDEO == "" or size(VIDEO) == 0 then
    io.stderr:write("用法: video_dub.sh <视频> \"文案1|文案2|…\" [--ref 参考.wav] [--voice 名] [--out out.mp4]\n")
    os.exit(2)
end
if not TEXT or TEXT == "" then
    io.stderr:write("缺文案（用 | 分隔每段）\n")
    os.exit(2)
end
local tf = read_file(TEXT)
if tf then TEXT = tf:gsub("\n", "|"):gsub("|$", "") end
if not OUT or OUT == "" then OUT = VIDEO:gsub("%.[^%.]*$", "") .. "_dubbed.mp4" end
if PROBE then FG = true end

local WORK, LOG, ASS, TMPVOICE = nil, nil, nil, ""

local function cleanup()
    if WORK then os.execute("rm -rf " .. q(WORK)) end
    if TMPVOICE ~= "" then
        os.execute(q(DIR .. "/../../voice/cosyvoice.sh") .. " del " .. q(TMPVOICE) .. " >/dev/null 2>&1")
        TMPVOICE = ""
    end
end

local function finish(code)
    cleanup()
    os.exit(code)
end

local function send_text(msg)
    local cmd = q(DIR .. "/wechat_send.sh")
    if TO ~= "" then cmd = cmd .. " --to " .. q(TO) end
    os.execute(cmd .. " " .. q(msg) .. " >/dev/null 2>&1")
end

local function split_segments(text)
    local seg = {}
    for p in (text .. "|"):gmatch("(.-)|") do if p ~= "" then seg[#seg + 1] = p end end
    return seg
end

local function pack_segments(seg)
    local all = table.concat(seg)
    local clauses = {}
    for line in (all:gsub("([，。！？、；：])", "%1\n") .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then clauses[#clauses + 1] = line end
    end
    local target = tonumber(os.getenv("VDUB_SEG_CHARS")) or 20
    local out, buf = {}, ""
    for _, c in ipairs(clauses) do
        if buf == "" then buf = c
        elseif #chars(buf) + #chars(c) <= target + 6 then buf = buf .. c
        else out[#out + 1] = buf; buf = c end
    end
    if buf ~= "" then out[#out + 1] = buf end
    return out
end

local function emit_subs(start, dur, text)
    local c = chars(clean_punct(text))
    local n = math.max(1, math.ceil(#c / 24))
    local dt = dur / n
    local f = assert(io.open(ASS, "a"))
    for k = 0, n - 1 do
        local part = table.concat(c, "", k * 24 + 1, math.min((k + 1) * 24, #c))
        if part ~= "" then
            f:write("Dialogue: 0,", timecode(start + k * dt), ",",
                timecode(start + (k + 1) * dt), ",Default,,0,0,0,,",
                wrap_text(part, 12), "\n")
        end
    end
    f:close()
end

local SEG, USE_VOICE

local function tts_all()
    for i2 = 1, #SEG do
        local wav = string.format("%s/aud/%d.wav", WORK, i2)
        local tx = SEG[i2]
        os.remove(wav)
        local used_clone = false
        if tx ~= "" and USE_VOICE ~= "" and size(vcfg.VOICES_DIR .. "/" .. USE_VOICE .. ".gguf") > 0 then
            os.execute(q(DIR .. "/../../voice/cosyvoice.sh") .. " synth " .. q(USE_VOICE) ..
                " " .. q(tx) .. " " .. q(wav) .. " " .. q(tostring(CLONE_SPEED)) ..
                " >>" .. q(LOG) .. " 2>&1")
            if size(wav) > 0 then used_clone = true end
        end
        if size(wav) == 0 then
            local ld = vcfg.SHERPA_LIB .. ":"
            local old = os.getenv("LD_LIBRARY_PATH")
            if old and old ~= "" then ld = ld .. old end
            local cmd = "LD_LIBRARY_PATH=" .. q(ld) .. " " .. q(vcfg.SHERPA_BIN) ..
                " --kokoro-model=" .. q(vcfg.KOKORO_DIR .. "/model.onnx") ..
                " --kokoro-voices=" .. q(vcfg.KOKORO_DIR .. "/voices.bin") ..
                " --kokoro-tokens=" .. q(vcfg.KOKORO_DIR .. "/tokens.txt") ..
                " --kokoro-data-dir=" .. q(vcfg.KOKORO_DIR .. "/espeak-ng-data") ..
                " --kokoro-lexicon=" .. q(vcfg.KOKORO_DIR .. "/lexicon-us-en.txt," .. vcfg.KOKORO_DIR .. "/lexicon-zh.txt") ..
                " --tts-rule-fsts=" .. q(vcfg.KOKORO_DIR .. "/date-zh.fst," .. vcfg.KOKORO_DIR .. "/number-zh.fst") ..
                " --num-threads=" .. tostring(vcfg.TTS_THREADS) ..
                " --sid=" .. tostring(vcfg.KOKORO_SID) ..
                " --output-filename=" .. q(wav) .. " " .. q(tx) ..
                " >>" .. q(LOG) .. " 2>&1"
            os.execute(cmd)
            if not used_clone and SPEED ~= 1 and size(wav) > 0 then
                local sp = string.format("%s/aud/sp_%d.wav", WORK, i2)
                if os.execute("ffmpeg -y -i " .. q(wav) .. " -filter:a " .. q("atempo=" .. SPEED) ..
                    " " .. q(sp) .. " >>" .. q(LOG) .. " 2>&1") == 0 then
                    os.remove(wav)
                    os.rename(sp, wav)
                end
            end
        end
    end
end

local function total_of()
    local sum = INTRO
    for k = 1, #SEG do
        local wav = string.format("%s/aud/%d.wav", WORK, k)
        if size(wav) > 0 then sum = sum + duration(wav) + PAUSE end
    end
    return sum
end

local function run_dub()
    local id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    WORK = "/tmp/vdub_" .. id
    LOG = "/tmp/vdub_" .. id .. ".log"
    ASS = WORK .. "/sub.ass"
    os.execute("mkdir -p " .. q(WORK .. "/aud"))
    local lf = io.open(LOG, "w")
    if lf then lf:write("[video_dub] start ", os.date("%T"), "\n"); lf:close() end

    local vd = duration(VIDEO) - SS - ET
    if vd < 1 then vd = 1 end

    SEG = pack_segments(split_segments(TEXT))
    if REF ~= "" and REF ~= "none" and size(REF) > 0 then
        if os.execute(q(DIR .. "/../../voice/cosyvoice.sh") .. " add _vdub_tmp " ..
            q(REF) .. " >>" .. q(LOG) .. " 2>&1") == 0 then
            TMPVOICE = "_vdub_tmp"
        end
    end
    USE_VOICE = TMPVOICE ~= "" and TMPVOICE or VOICE

    tts_all()
    local total = total_of()
    local attempt = 0
    while FIT and total > vd + 0.01 and attempt < 4 do
        attempt = attempt + 1
        local factor = (vd - 1.5) / (total - 1.5) * 0.95
        if factor > 0.99 then factor = 0.99 end
        local lf2 = io.open(LOG, "a")
        if lf2 then lf2:write(string.format("  · 超出（%.2fs>%.2fs），第 %d 次精简 ×%.2f\n", total, vd, attempt, factor)); lf2:close() end
        for j = 1, #SEG do
            local c = chars(SEG[j])
            local newlen = math.max(6, math.floor(#c * factor))
            SEG[j] = table.concat(c, "", 1, math.min(newlen, #c))
        end
        tts_all()
        total = total_of()
    end
    if total > vd + 0.01 then
        local msg = string.format("自动精简后仍超出视频时长（约 %.2fs / %.2fs），请删减文案。", total, vd)
        io.stderr:write(msg .. "\n")
        if TO ~= "" then send_text(msg) end
        finish(1)
    end
    local lf3 = io.open(LOG, "a")
    if lf3 then lf3:write(string.format("  · 配音总时长 %.2fs / 视频 %.2fs（精简 %d 次）\n", total, vd, attempt)); lf3:close() end

    if PROBE then
        print(string.format("视频 %.2fs ｜ 配音 %.2fs ｜ 精简 %d 次 ｜ 段数 %d", vd, total, attempt, #SEG))
        for k = 1, #SEG do
            local wav = string.format("%s/aud/%d.wav", WORK, k)
            if size(wav) > 0 then
                print(string.format("  段%d: %.2fs  %s", k, duration(wav), SEG[k]))
            end
        end
        finish(0)
    end

    local af = assert(io.open(ASS, "w"))
    af:write("[Script Info]\nTitle: Video Dub\nScriptType: v4.00+\nWrapStyle: 1\n" ..
        "ScaledBorderAndShadow: yes\nYCbCr Matrix: None\n\n[V4+ Styles]\n" ..
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n" ..
        "Style: " .. FONT_STYLE .. "\n\n[Events]\n" ..
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")
    af:close()

    local cur = INTRO
    for k = 1, #SEG do
        local wav = string.format("%s/aud/%d.wav", WORK, k)
        if size(wav) > 0 then
            local d = duration(wav)
            emit_subs(cur, d, SEG[k])
            cur = cur + d + PAUSE
        end
    end

    local al = assert(io.open(WORK .. "/alist.txt", "w"))
    for k = 1, #SEG do
        local wav = string.format("%s/aud/%d.wav", WORK, k)
        if size(wav) > 0 then
            local pad = string.format("%s/aud/pad_%d.wav", WORK, k)
            os.execute("ffmpeg -y -i " .. q(wav) .. " -af " .. q("apad=pad_dur=" .. PAUSE) ..
                " " .. q(pad) .. " >>" .. q(LOG) .. " 2>&1")
            al:write("file '" .. pad .. "'\n")
        end
    end
    al:close()
    os.execute("ffmpeg -y -f concat -safe 0 -i " .. q(WORK .. "/alist.txt") ..
        " -c:a aac " .. q(WORK .. "/voice.aac") .. " >>" .. q(LOG) .. " 2>&1")
    os.execute("ffmpeg -y -f lavfi -t " .. tostring(INTRO) ..
        " -i anullsrc=r=24000:cl=mono " .. q(WORK .. "/sil.m4a") .. " >>" .. q(LOG) .. " 2>&1")
    local ff = assert(io.open(WORK .. "/final.txt", "w"))
    ff:write("file '" .. WORK .. "/sil.m4a'\nfile '" .. WORK .. "/voice.aac'\n")
    ff:close()
    os.execute("ffmpeg -y -f concat -safe 0 -i " .. q(WORK .. "/final.txt") ..
        " -c:a aac " .. q(WORK .. "/narration.aac") .. " >>" .. q(LOG) .. " 2>&1")

    local has_audio = capture("ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 " .. q(VIDEO)):match("%d+") ~= nil
    local cmd
    if KEEPAUDIO and has_audio then
        local fc = "[0:a]volume=0.35[a0];[1:a]volume=1.5[a1];[a0][a1]amix=inputs=2:duration=first:dropout_transition=2[aout]"
        cmd = "ffmpeg -y -ss " .. tostring(SS) .. " -t " .. string.format("%.3f", vd) ..
            " -i " .. q(VIDEO) .. " -i " .. q(WORK .. "/narration.aac") ..
            " -filter_complex " .. q(fc) .. " -map 0:v -map " .. q("[aout]") ..
            " -vf " .. q("ass=" .. ASS) .. " -c:v libx264 -c:a aac " .. q(OUT) ..
            " >>" .. q(LOG) .. " 2>&1"
    else
        cmd = "ffmpeg -y -ss " .. tostring(SS) .. " -t " .. string.format("%.3f", vd) ..
            " -i " .. q(VIDEO) .. " -i " .. q(WORK .. "/narration.aac") ..
            " -vf " .. q("ass=" .. ASS) .. " -af " .. q("volume=1.5") ..
            " -map 0:v -map 1:a -c:v libx264 -c:a aac " .. q(OUT) ..
            " >>" .. q(LOG) .. " 2>&1"
    end
    os.execute(cmd)

    if size(OUT) > 0 then
        local lf4 = io.open(LOG, "a"); if lf4 then lf4:write("[video_dub] done -> " .. OUT .. "\n"); lf4:close() end
        if not NOSEND then
            local sc = q(DIR .. "/wechat_send_file.sh") .. " " .. q(OUT)
            if TO ~= "" then sc = sc .. " --to " .. q(TO) end
            os.execute(sc .. " >/dev/null 2>&1")
        end
    else
        io.stderr:write("合成失败，日志: " .. LOG .. "\n")
        finish(1)
    end
    cleanup()
end

if FG or os.getenv("VIDEO_DUB_RUN") == "1" then
    os.execute("touch /tmp/video_dub.lock")
    local fd = ffi.C.open("/tmp/video_dub.lock", 2)
    if fd >= 0 then ffi.C.flock(fd, 2) end
    run_dub()
else
    local id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    local outlog = "/tmp/vdub_" .. id .. ".out"
    local parts = { "setsid", "env", "VIDEO_DUB_RUN=1", "luajit", q(DIR .. "/video_dub.lua") }
    for _, a in ipairs(arg) do parts[#parts + 1] = q(a) end
    os.execute(table.concat(parts, " ") .. " </dev/null >" .. q(outlog) .. " 2>&1 &")
    print("已后台开始配音+字幕（串行排队），完成后文件在 " .. OUT ..
        (NOSEND and "（未发微信）" or ""))
end
