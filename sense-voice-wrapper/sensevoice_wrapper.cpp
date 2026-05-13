/**
 * SenseVoice C Wrapper - 提供 C 接口供 Python ctypes 调用
 * 
 * 功能：
 * - 加载模型（一次加载，多次识别）
 * - 识别音频文件
 * - 返回文本结果
 * 
 * 编译：
 *   cd /home/dministrator/SenseVoice.cpp
 *   g++ -shared -fPIC -std=c++17 \
 *     -I. -Isense-voice/csrc -Ibuild/_deps/ggml-src/include \
 *     sense-voice/csrc/sensevoice_wrapper.cpp \
 *     build/lib/libsense-voice-core.a \
 *     build/lib/libcommon.a \
 *     -Lbuild/lib -lggml -lggml-base -lggml-cpu \
 *     -o libsensevoice.so \
 *     -lpthread -ldl
 */

#include <cstdio>
#include <cstring>
#include <cstdarg>
#include <vector>
#include <sstream>

// 包含 SenseVoice 头文件
#include "sense-voice.h"
#include "sense-voice-frontend.h"

extern "C" {

// 隐藏 stdout 的辅助函数
static std::string g_last_output;
static bool g_capture_output = false;

// 重定向 printf 到字符串
static int custom_printf(const char* fmt, ...) {
    if (!g_capture_output) {
        va_list args;
        va_start(args, fmt);
        int ret = vprintf(fmt, args);
        va_end(args);
        return ret;
    }
    
    va_list args;
    va_start(args, fmt);
    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    
    g_last_output += buf;
    return strlen(buf);
}

/**
 * 加载模型
 * @param model_path 模型文件路径（如 "models/sense-voice-small-q6_k.gguf"）
 * @param use_gpu 是否使用 GPU
 * @return handle 模型句柄（NULL 表示失败）
 */
void* sensevoice_load_model(const char* model_path, int use_gpu) {
    struct sense_voice_context_params cparams = sense_voice_context_default_params();
    cparams.use_gpu = use_gpu != 0;
    cparams.use_itn = true;  // 使用逆文本正则化（包含标点）
    cparams.flash_attn = false;
    
    struct sense_voice_context* ctx = sense_voice_small_init_from_file_with_params(model_path, cparams);
    
    if (ctx == nullptr) {
        fprintf(stderr, "[SenseVoice] 模型加载失败: %s\n", model_path);
        return nullptr;
    }
    
    // 设置语言为 auto（自动检测）
    ctx->language_id = sense_voice_lang_id("auto");
    
    printf("[SenseVoice] 模型加载成功: %s\n", model_path);
    return ctx;
}

/**
 * 识别音频文件
 * @param handle 模型句柄
 * @param wav_path WAV 文件路径（必须是 16kHz 单声道）
 * @param n_threads 线程数
 * @return 识别文本（需要调用 sensevoice_free_text 释放）
 */
const char* sensevoice_recognize(void* handle, const char* wav_path, int n_threads) {
    struct sense_voice_context* ctx = (struct sense_voice_context*)handle;
    if (ctx == nullptr) {
        return strdup("[错误] 模型未加载");
    }
    
    // 加载 WAV 文件
    std::vector<double> pcmf32;
    int sample_rate;
    if (!load_wav_file(wav_path, &sample_rate, pcmf32)) {
        return strdup("[错误] 无法读取 WAV 文件");
    }
    
    // 设置识别参数
    sense_voice_full_params wparams = sense_voice_full_default_params(SENSE_VOICE_SAMPLING_GREEDY);
    wparams.strategy = SENSE_VOICE_SAMPLING_GREEDY;
    wparams.language = "auto";
    wparams.n_threads = n_threads > 0 ? n_threads : 4;
    wparams.offset_ms = 0;
    wparams.duration_ms = 0;
    wparams.debug_mode = false;
    wparams.greedy.best_of = 5;
    wparams.no_timestamps = false;
    
    // 执行识别
    if (sense_voice_full_parallel(ctx, wparams, pcmf32, pcmf32.size(), 1) != 0) {
        return strdup("[错误] 识别失败");
    }
    
    // 提取文本结果
    std::string result;
    bool use_prefix = true;
    bool use_itn = true;
    
    for (size_t i = (use_prefix ? 0 : 4); i < ctx->state->ids.size(); i++) {
        int id = ctx->state->ids[i];
        if (i > 0 && ctx->state->ids[i - 1] == ctx->state->ids[i])
            continue;
        if (id && ctx->vocab.id_to_token.count(id)) {
            result += ctx->vocab.id_to_token[id];
        }
    }
    
    // 不释放 state，让它重用（state 内存占用不大，重用可提高性能）
    
    // 使用静态缓冲区避免动态分配问题
    static char g_result_buffer[4096];
    strncpy(g_result_buffer, result.c_str(), sizeof(g_result_buffer) - 1);
    g_result_buffer[sizeof(g_result_buffer) - 1] = '\0';
    return g_result_buffer;
}

/**
 * 释放模型
 * @param handle 模型句柄
 */
void sensevoice_free_model(void* handle) {
    struct sense_voice_context* ctx = (struct sense_voice_context*)handle;
    if (ctx) {
        sense_voice_free(ctx);
        printf("[SenseVoice] 模型已释放\n");
    }
}

/**
 * 释放文本内存
 * @param text sensevoice_recognize 返回的文本
 */
void sensevoice_free_text(const char* text) {
    // 现在使用静态缓冲区，不需要释放
    // if (text) {
    //     free((void*)text);
    // }
}

} // extern "C"
