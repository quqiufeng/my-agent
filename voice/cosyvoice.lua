local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local cfg = require("config")
local audio = require("audio")

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function write_file(path, s)
    local f = io.open(path, "w")
    if f then f:write(s); f:close() end
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function synth(name, text, out, speed)
    local gguf = cfg.VOICES_DIR .. "/" .. name .. ".gguf"
    if not file_exists(gguf) then
        io.stderr:write("音色不存在: " .. name .. "（用 cosyvoice.sh add 注册）\n")
        return false
    end
    local ld = cfg.COSYVOICE_LIB_DIR .. ":" .. cfg.COSYVOICE_BIN_DIR .. ":"
    local old = os.getenv("LD_LIBRARY_PATH")
    if old and old ~= "" then ld = ld .. old end
    local cmd = "LD_LIBRARY_PATH=" .. q(ld) .. " luajit " ..
        q(DIR .. "/cosyvoice_tts.lua") .. " " .. q(gguf) .. " " .. q(out) ..
        " " .. q(text) .. " " .. q(speed or "1.0")
    return os.execute(cmd) == 0
end

local function transcribe(wav)
    local tmp = "/tmp/cv_asr_" .. tostring(os.time()) .. ".wav"
    if os.execute("ffmpeg -y -i " .. q(wav) .. " -ar 16000 -ac 1 -c:a pcm_s16le " ..
        q(tmp) .. " >/dev/null 2>&1") ~= 0 then
        tmp = wav
    end
    local cmd = q(cfg.SENSEVOICE_BIN) .. " -m " .. q(cfg.SENSEVOICE_MODEL) ..
        " -ng -t " .. tostring(cfg.SENSEVOICE_THREADS) ..
        " -l " .. q(cfg.SENSEVOICE_LANG) .. " " .. q(tmp) .. " 2>/dev/null"
    local p = io.popen(cmd)
    local out = p and (p:read("*a") or "") or ""
    if p then p:close() end
    if tmp ~= wav then os.remove(tmp) end
    out = out:gsub("<|.-|>", ""):gsub("%[[%d%.]+%-[%d%.]+%]", "")
    out = out:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if out:find("gdb", 1, true) or out:find("LWP", 1, true)
        or out:find("Inferior", 1, true) or out:find("subchunk", 1, true) then
        return nil
    end
    return out
end

local cmd = arg[1] or ""
os.execute("mkdir -p " .. q(cfg.VOICES_DIR) .. " 2>/dev/null")

if cmd == "list" then
    local p = io.popen("ls -1 " .. q(cfg.VOICES_DIR) .. "/*.gguf 2>/dev/null")
    local found = false
    if p then
        for line in p:lines() do
            found = true
            local name = line:match("([^/]+)%.gguf$") or line
            local txt = read_file(cfg.VOICES_DIR .. "/" .. name .. ".txt") or ""
            txt = txt:gsub("%s+$", "")
            print(string.format("%-20s %s", name, txt))
        end
        p:close()
    end
    if not found then print("(无音色；用 cosyvoice.sh add <名> <参考.wav> 注册)") end
elseif cmd == "add" then
    local name, ref, txt = arg[2], arg[3], arg[4] or ""
    if not name or name == "" or not ref or not file_exists(ref) then
        io.stderr:write("用法: cosyvoice.sh add <名> <参考.wav> [参考文本]\n")
        os.exit(2)
    end
    if txt == "" then
        print("未给参考文本，用 SenseVoice 自动转写(CPU)...")
        txt = transcribe(ref) or ""
        if txt == "" then
            io.stderr:write("转写失败，请手动提供参考文本：cosyvoice.sh add " ..
                name .. " <ref.wav> \"文本\"\n")
            os.exit(1)
        end
        print("  文本: " .. txt)
    end
    local gguf = cfg.VOICES_DIR .. "/" .. name .. ".gguf"
    local log = "/tmp/cosyvoice_add.log"
    local add = q(cfg.COSYVOICE_CLI) .. " --frontend-only" ..
        " --speech-tokenizer " .. q(cfg.COSYVOICE_TOKENIZER) ..
        " --campplus " .. q(cfg.COSYVOICE_CAMPPLUS) ..
        " --prompt-audio " .. q(ref) ..
        " --prompt-text " .. q(txt) ..
        " --prompt-speech-output " .. q(gguf) ..
        " >" .. q(log) .. " 2>&1"
    if os.execute(add) ~= 0 then
        io.stderr:write("注册失败，日志：\n")
        local p = io.popen("tail -15 " .. q(log) .. " 2>/dev/null")
        if p then io.write(p:read("*a") or ""); p:close() end
        os.exit(1)
    end
    os.execute("cp -f " .. q(ref) .. " " .. q(cfg.VOICES_DIR .. "/" .. name .. ".wav") ..
        " 2>/dev/null")
    write_file(cfg.VOICES_DIR .. "/" .. name .. ".txt", txt)
    print("已注册音色: " .. name .. "  (文本: " .. txt .. ")")
elseif cmd == "synth" then
    local name, text = arg[2], arg[3]
    local out = arg[4] or "/tmp/cosyvoice_out.wav"
    local speed = arg[5] or "1.0"
    if not name or not text then
        io.stderr:write("用法: cosyvoice.sh synth <名> \"文本\" <out.wav> [语速]\n")
        os.exit(2)
    end
    if not synth(name, text, out, speed) then os.exit(1) end
    print(out)
elseif cmd == "del" then
    local name = arg[2]
    if not name then io.stderr:write("用法: cosyvoice.sh del <名>\n"); os.exit(2) end
    for _, ext in ipairs({ ".gguf", ".wav", ".txt" }) do
        os.remove(cfg.VOICES_DIR .. "/" .. name .. ext)
    end
    print("已删除音色: " .. name)
elseif cmd == "say" or cmd == "speak" then
    local name, text = arg[2], arg[3]
    local speed = arg[4] or "1.0"
    if not name or not text then
        io.stderr:write("用法: cosyvoice.sh speak <名> \"文本\" [语速]\n")
        os.exit(2)
    end
    local out = cfg.TTS_OUT or "/tmp/voice_tts.wav"
    if not synth(name, text, out, speed) then os.exit(1) end
    audio.play(out, cfg)
else
    io.stderr:write("用法: cosyvoice.sh {list | add <名> <参考.wav> [文本] | synth <名> \"文本\" <out.wav> | speak <名> \"文本\"}\n")
    os.exit(2)
end
