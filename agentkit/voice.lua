-- agentkit/voice.lua — 语音能力（ASR/TTS/录音）
-- 复用 my-agent 已有 C++：SenseVoice.cpp（语音转文字）、sherpa-onnx + Kokoro（文字转语音）
local M = {}

-- ── 配置（可用环境变量覆盖）───────────────────────────
local CFG = {
    asr_bin   = os.getenv("SENSEVOICE_BIN")   or "/opt/SenseVoice.cpp/bin/sense-voice-main",
    asr_model = os.getenv("SENSEVOICE_MODEL") or "/data/models/sense-voice-small-q4_k.gguf",
    asr_lang  = os.getenv("SENSEVOICE_LANG")  or "zh",
    threads   = os.getenv("SENSEVOICE_THREADS") or "4",
    say_sh    = os.getenv("AGENTKIT_SAY")     or "/opt/my-agent/voice/say.sh",
    tts_out   = os.getenv("TTS_OUT")          or "/tmp/voice_tts.wav",
    mic_dev   = os.getenv("VOICE_MIC_DEV")    or "plughw:2,0",
}
M.cfg = CFG

local function sh(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return "", 1 end
    local o = f:read("*a") or ""
    local ok = f:close()
    return o, ok
end
M.sh = sh

-- 文本转语音：合成 WAV（默认同时播放到音响），返回 wav 路径
-- opts = { sid=<Kokoro音色ID>, play=(默认 true), out=<路径> }
function M.tts(text, opts)
    opts = opts or {}
    local out = opts.out or CFG.tts_out
    local env = ""
    if opts.sid then env = env .. ("KOKORO_SID=%s "):format(tostring(opts.sid)) end
    if opts.out then env = env .. ("TTS_OUT=%s "):format(opts.out) end
    if opts.play == false then
        -- say.sh 总是播放；如需静默合成可用 sherpa 二进制（此处占位）
    end
    local cmd = ("%s%s %q"):format(env, CFG.say_sh, text)
    local _, ok = sh(cmd)
    return out, ok
end

-- 语音转文字：返回纯文本（自动去掉 SenseVoice 特殊标签）
-- opts = { lang=, wav=, raw=(返回带时间戳的行) }
function M.asr(wav, opts)
    opts = opts or {}
    local lang = opts.lang or CFG.asr_lang
    local cmd = ("%s -m %s -l %s -t %s -f %q"):format(
        CFG.asr_bin, CFG.asr_model, lang, CFG.threads, wav)
    local out = sh(cmd)
    local lines = {}
    for t0, t1, txt in out:gmatch("%[([%d%.]+)%-([%d%.]+)%]%s*([^\n]+)") do
        txt = txt:gsub("<[^>]*>", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if txt ~= "" then
            if opts.raw then
                lines[#lines + 1] = { t0 = tonumber(t0), t1 = tonumber(t1), text = txt }
            else
                lines[#lines + 1] = txt
            end
        end
    end
    if opts.raw then return lines end
    return table.concat(lines, "")
end

-- 录音：sec 秒 → wav（16k 单声道）
function M.record(sec, out, opts)
    opts = opts or {}
    local dev = opts.dev or CFG.mic_dev
    out = out or "/tmp/agentkit_rec.wav"
    sh(("arecord -D %s -f S16_LE -r 16000 -c 1 -d %s %q"):format(dev, tostring(sec), out))
    return out
end

-- 录一句并识别（VAD 简化版：固定时长）
function M.listen_once(sec, opts)
    local wav = M.record(sec or 4, nil, opts)
    return M.asr(wav, opts), wav
end

-- 播放 wav（PipeWire 优先，回退 aplay）
function M.play(wav, sink)
    local cmd
    if sink and sink ~= "" then
        cmd = ("pw-play %q"):format(wav)
    else
        cmd = ("pw-play %q 2>/dev/null || aplay -q %q"):format(wav, wav)
    end
    sh(cmd)
end

return M
