local home = os.getenv("HOME") or "/root"

local function env(key, default)
    local v = os.getenv(key)
    if v == nil then return default end
    return v
end

local M = {
    SENSEVOICE_BIN = env("SENSEVOICE_BIN", "/opt/SenseVoice.cpp/bin/sense-voice-main"),
    SENSEVOICE_MODEL = env("SENSEVOICE_MODEL", "/data/models/sense-voice-small-q4_k.gguf"),
    SENSEVOICE_LANG = env("SENSEVOICE_LANG", "zh"),
    SENSEVOICE_THREADS = tonumber(env("SENSEVOICE_THREADS", "4")) or 4,
    VOICE_MIC_DEV = env("VOICE_MIC_DEV", "plughw:2,0"),
    VOICE_MIC_CARD = env("VOICE_MIC_CARD", "2"),
    VOICE_MIC_GAIN = env("VOICE_MIC_GAIN", "7810"),

    SHERPA_BIN = env("SHERPA_BIN", "/opt/sherpa-onnx/bin/sherpa-onnx-offline-tts"),
    SHERPA_LIB = env("SHERPA_LIB", "/opt/sherpa-onnx/lib"),
    KOKORO_DIR = env("KOKORO_DIR", "/data/models/kokoro-multi-lang-v1_0"),
    KOKORO_SID = env("KOKORO_SID", "47"),
    TTS_THREADS = tonumber(env("TTS_THREADS", "4")) or 4,
    VOICE_SPEAKER = env("VOICE_SPEAKER", "plughw:3,0"),
    VOICE_SINK = env("VOICE_SINK", ""),
    TTS_OUT = env("TTS_OUT", "/tmp/voice_tts.wav"),

    COSYVOICE_LIB_DIR = env("COSYVOICE_LIB_DIR", "/opt/cosyvoice.cpp/build/lib"),
    COSYVOICE_BIN_DIR = env("COSYVOICE_BIN_DIR", "/opt/cosyvoice.cpp/build/bin"),
    COSYVOICE_CLI = env("COSYVOICE_CLI", "/opt/cosyvoice.cpp/build/bin/cosyvoice-cli"),
    COSYVOICE_MODEL = env("COSYVOICE_MODEL", "/data/models/cosyvoice3-gguf/CosyVoice3-2512_F16.gguf"),
    COSYVOICE_TOKENIZER = env("COSYVOICE_TOKENIZER", "/data/models/Fun-CosyVoice3-0.5B/speech_tokenizer_v3.onnx"),
    COSYVOICE_CAMPPLUS = env("COSYVOICE_CAMPPLUS", "/data/models/Fun-CosyVoice3-0.5B/campplus.onnx"),
    VOICES_DIR = env("VOICES_DIR", home .. "/.myagent_voices"),
    SAY_VOICE = env("SAY_VOICE", ""),

    VOICE_PREFIX = env("VOICE_PREFIX", "[语音输入]"),
    VOICE_ALWAYS = env("VOICE_ALWAYS", "0"),
    KOKORO_SID_EN = env("KOKORO_SID_EN", "3"),
    SENSEVOICE_LANG_EN = env("SENSEVOICE_LANG_EN", "auto"),
    VOICE_WAKE = env("VOICE_WAKE", "你好星期五,星期五"),
    VOICE_ACTIVE_MS = env("VOICE_ACTIVE_MS", "10000"),
    AGENT_URL = env("AGENT_URL", "http://localhost:4097"),
}

return M
