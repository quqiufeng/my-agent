local DIR = (arg[0] or ""):match("^(.*)/") or "."
package.path = DIR .. "/?.lua;" .. package.path
local cfg = require("config")
local audio = require("audio")

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function finish(code)
    os.remove("/tmp/myagent_tts_active")
    os.exit(code)
end

local voice_override, text = "", ""
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--voice" then voice_override = arg[i + 1] or ""; i = i + 2
    elseif a == "--kokoro" then voice_override = "__kokoro__"; i = i + 1
    else
        text = text .. (text ~= "" and " " or "") .. a
        i = i + 1
    end
end

if text == "" then
    io.stderr:write("用法: say.sh [--voice 音色名] <文本>\n")
    os.exit(2)
end

if io.open("/tmp/myagent_english_mode", "r") then
    cfg.KOKORO_SID = cfg.KOKORO_SID_EN
end

local flag = io.open("/tmp/myagent_tts_active", "w")
if flag then flag:close() end

local wav = cfg.TTS_OUT
local voice = voice_override ~= "" and voice_override or cfg.SAY_VOICE

if voice ~= "" and voice ~= "__kokoro__" then
    local gguf = cfg.VOICES_DIR .. "/" .. voice .. ".gguf"
    local f = io.open(gguf, "rb")
    if f then
        f:close()
        if os.execute("luajit " .. q(DIR .. "/cosyvoice.lua") .. " speak " ..
            q(voice) .. " " .. q(text)) == 0 then finish(0) end
        io.stderr:write("[say] 克隆音色合成失败，回退 Kokoro\n")
    end
end

local ok = false
local sherpa_ok = os.execute("test -x " .. q(cfg.SHERPA_BIN) .. " >/dev/null 2>&1") == 0
local model_ok = io.open(cfg.KOKORO_DIR .. "/model.onnx", "rb") ~= nil
if sherpa_ok and model_ok then
    local ld = cfg.SHERPA_LIB .. ":"
    local old = os.getenv("LD_LIBRARY_PATH")
    if old and old ~= "" then ld = ld .. old end
    local cmd = "LD_LIBRARY_PATH=" .. q(ld) .. " " .. q(cfg.SHERPA_BIN) ..
        " --kokoro-model=" .. q(cfg.KOKORO_DIR .. "/model.onnx") ..
        " --kokoro-voices=" .. q(cfg.KOKORO_DIR .. "/voices.bin") ..
        " --kokoro-tokens=" .. q(cfg.KOKORO_DIR .. "/tokens.txt") ..
        " --kokoro-data-dir=" .. q(cfg.KOKORO_DIR .. "/espeak-ng-data") ..
        " --kokoro-lexicon=" .. q(cfg.KOKORO_DIR .. "/lexicon-us-en.txt," .. cfg.KOKORO_DIR .. "/lexicon-zh.txt") ..
        " --tts-rule-fsts=" .. q(cfg.KOKORO_DIR .. "/date-zh.fst," .. cfg.KOKORO_DIR .. "/number-zh.fst") ..
        " --num-threads=" .. tostring(cfg.TTS_THREADS) ..
        " --sid=" .. tostring(cfg.KOKORO_SID) ..
        " --output-filename=" .. q(wav) .. " " .. q(text) .. " >/dev/null 2>&1"
    if os.execute(cmd) == 0 then ok = true end
end

if not ok then
    io.stderr:write("[say] Kokoro 不可用，回退 espeak-ng\n")
    if os.execute("espeak-ng -v cmn -w " .. q(wav) .. " " .. q(text) ..
        " 2>/dev/null") ~= 0 then
        io.stderr:write("[say] espeak-ng 也失败\n")
        finish(1)
    end
end

audio.play(wav, cfg)
finish(0)
