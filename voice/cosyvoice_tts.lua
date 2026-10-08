-- voice/cosyvoice_tts.lua — LuaJIT FFI 调 libcosyvoice.so 做零样本克隆合成
-- 用法: luajit cosyvoice_tts.lua <prompt_speech.gguf> <out.wav> <text> [speed]
-- 依赖环境: COSYVOICE_LIB_DIR(build/lib), COSYVOICE_BIN_DIR(build/bin), COSYVOICE_MODEL(model.gguf)
--   libcosyvoice/ggml 由 LD_LIBRARY_PATH 解析；缺失时脚本自动补上默认路径。
local ffi = require("ffi")

ffi.cdef[[
typedef struct cosyvoice_context* cosyvoice_context_t;
typedef struct cosyvoice_prompt_speech* cosyvoice_prompt_speech_t;
typedef struct cosyvoice_prompt* cosyvoice_prompt_t;
typedef struct cosyvoice_tts_context* cosyvoice_tts_context_t;
typedef struct cosyvoice_generated_speech { float* data; uint32_t length; } *cosyvoice_generated_speech_ptr;

void cosyvoice_init_backend_from_path(const char* dir_path);
cosyvoice_context_t cosyvoice_load_from_file(const char* filename);
uint32_t cosyvoice_get_sample_rate(cosyvoice_context_t);
cosyvoice_prompt_speech_t cosyvoice_prompt_speech_load_from_file(const char* filename);
cosyvoice_prompt_t cosyvoice_prompt_init_from_prompt_speech(cosyvoice_context_t, cosyvoice_prompt_speech_t);
cosyvoice_tts_context_t cosyvoice_tts_context_new(cosyvoice_context_t, cosyvoice_prompt_t);
bool cosyvoice_tts_zero_shot(cosyvoice_tts_context_t, const char* text, float speed, cosyvoice_generated_speech_ptr result);
bool cosyvoice_save_wav(const char* filename, const float* data, uint32_t len, uint32_t sr);
void cosyvoice_free(cosyvoice_context_t);
void cosyvoice_prompt_speech_free(cosyvoice_prompt_speech_t);
void cosyvoice_prompt_free(cosyvoice_prompt_t);
void cosyvoice_tts_context_free(cosyvoice_tts_context_t);
]]

local ps_path = arg[1]
local out_path = arg[2]
local text = arg[3]
local speed = tonumber(arg[4] or "1.0") or 1.0
if not (ps_path and out_path and text) then
    io.stderr:write("用法: luajit cosyvoice_tts.lua <prompt_speech.gguf> <out.wav> \"文本\" [speed]\n")
    os.exit(2)
end

local LIB_DIR = os.getenv("COSYVOICE_LIB_DIR") or "/opt/cosyvoice.cpp/build/lib"
local BIN_DIR = os.getenv("COSYVOICE_BIN_DIR") or "/opt/cosyvoice.cpp/build/bin"
local MODEL   = os.getenv("COSYVOICE_MODEL")   or "/data/models/cosyvoice3-gguf/CosyVoice3-2512_F16.gguf"

-- 保证动态库可被找到
local ld = os.getenv("LD_LIBRARY_PATH") or ""
if not ld:find(LIB_DIR, 1, true) then
    os.setenv("LD_LIBRARY_PATH", LIB_DIR .. ":" .. BIN_DIR .. ":" .. ld)
end

local ok_load, lib = pcall(ffi.load, "cosyvoice")
if not ok_load then lib = ffi.load(LIB_DIR .. "/libcosyvoice.so") end

lib.cosyvoice_init_backend_from_path(BIN_DIR)
local ctx = lib.cosyvoice_load_from_file(MODEL)
if ctx == nil then io.stderr:write("[cosyvoice] 载入模型失败: " .. MODEL .. "\n"); os.exit(1) end

local psp = lib.cosyvoice_prompt_speech_load_from_file(ps_path)
if psp == nil then io.stderr:write("[cosyvoice] 载入音色失败: " .. ps_path .. "\n"); lib.cosyvoice_free(ctx); os.exit(1) end

local prompt = lib.cosyvoice_prompt_init_from_prompt_speech(ctx, psp)
local ttsctx = lib.cosyvoice_tts_context_new(ctx, prompt)
local res = ffi.new("struct cosyvoice_generated_speech[1]")

local ok = lib.cosyvoice_tts_zero_shot(ttsctx, text, speed, res)
if not ok then
    io.stderr:write("[cosyvoice] 合成失败\n")
else
    local sr = lib.cosyvoice_get_sample_rate(ctx)
    lib.cosyvoice_save_wav(out_path, res[0].data, res[0].length, sr)
    print(string.format("[cosyvoice] 已生成 %s (%.2fs @%dHz)", out_path, tonumber(res[0].length) / sr, sr))
end

lib.cosyvoice_tts_context_free(ttsctx)
lib.cosyvoice_prompt_free(prompt)
lib.cosyvoice_prompt_speech_free(psp)
lib.cosyvoice_free(ctx)
os.exit(ok and 0 or 1)
