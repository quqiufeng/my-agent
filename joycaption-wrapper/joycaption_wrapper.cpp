/**
 * JoyCaption C Wrapper - 提供 C 接口供 Python ctypes 调用
 * 
 * 功能：
 * - 加载模型（LLM + mmproj，常驻内存）
 * - 分析图片并生成描述
 * - 返回文本结果
 * 
 * 基于 llama.cpp mtmd C API
 * 
 * 编译：
 *   cd ~/llama.cpp
 *   g++ -shared -fPIC -std=c++17 \
 *     -I. -Iinclude -Icommon -Itools/mtmd -Iexamples -Iggml/include \
 *     -Lbuild/bin -lmtmd -lllama -lcommon -lggml -lggml-base -lggml-cpu -lggml-cuda \
 *     -L/usr/local/cuda-12.0/lib64 -lcudart -lcublas \
 *     joycaption_wrapper.cpp \
 *     -o libjoycaption.so \
 *     -lpthread -ldl
 */

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <memory>

// llama.cpp headers
#include "llama.h"
#include "common.h"
#include "sampling.h"
#include "mtmd.h"
#include "mtmd-helper.h"

extern "C" {

// 全局状态
static struct {
    llama_model* model = nullptr;
    llama_context* lctx = nullptr;
    const llama_vocab* vocab = nullptr;
    mtmd_context* ctx_vision = nullptr;
    common_sampler* smpl = nullptr;
    bool initialized = false;
    int n_threads = 4;
} g_state;

// 静态结果缓冲区
static char g_result_buffer[8192];

// 辅助函数：batch clear
static void batch_clear(struct llama_batch & batch) {
    batch.n_tokens = 0;
}

// 辅助函数：batch add
static void batch_add(struct llama_batch & batch, llama_token id, llama_pos pos, 
                      const std::vector<llama_seq_id> & seq_ids, bool logits) {
    batch.token[batch.n_tokens] = id;
    batch.pos[batch.n_tokens] = pos;
    batch.n_seq_id[batch.n_tokens] = seq_ids.size();
    for (size_t i = 0; i < seq_ids.size(); i++) {
        batch.seq_id[batch.n_tokens][i] = seq_ids[i];
    }
    batch.logits[batch.n_tokens] = logits;
    batch.n_tokens++;
}

/**
 * 初始化模型
 * @param model_path LLM 模型路径
 * @param mmproj_path mmproj 路径
 * @param use_gpu 是否使用 GPU
 * @return 0 成功，-1 失败
 */
int joycaption_init(const char* model_path, const char* mmproj_path, int use_gpu) {
    if (g_state.initialized) {
        fprintf(stderr, "[JoyCaption] 已初始化\n");
        return -1;
    }

    // 1. 初始化 llama backend
    llama_backend_init();
    llama_numa_init(GGML_NUMA_STRATEGY_DISABLED);

    // 2. 加载模型
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = use_gpu ? 999 : 0;
    
    g_state.model = llama_model_load_from_file(model_path, model_params);
    if (g_state.model == nullptr) {
        fprintf(stderr, "[JoyCaption] 模型加载失败: %s\n", model_path);
        return -1;
    }

    g_state.vocab = llama_model_get_vocab(g_state.model);

    // 3. 创建上下文
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = 4096;
    ctx_params.n_batch = 2048;
    ctx_params.n_threads = g_state.n_threads;
    ctx_params.n_threads_batch = g_state.n_threads;

    g_state.lctx = llama_init_from_model(g_state.model, ctx_params);
    if (g_state.lctx == nullptr) {
        fprintf(stderr, "[JoyCaption] 上下文创建失败\n");
        llama_model_free(g_state.model);
        g_state.model = nullptr;
        return -1;
    }

    // 4. 加载 mmproj
    mtmd_context_params mtmd_params = mtmd_context_params_default();
    mtmd_params.use_gpu = use_gpu != 0;
    mtmd_params.n_threads = g_state.n_threads;
    mtmd_params.warmup = true;

    g_state.ctx_vision = mtmd_init_from_file(mmproj_path, g_state.model, mtmd_params);
    if (g_state.ctx_vision == nullptr) {
        fprintf(stderr, "[JoyCaption] mmproj 加载失败: %s\n", mmproj_path);
        llama_free(g_state.lctx);
        llama_model_free(g_state.model);
        g_state.lctx = nullptr;
        g_state.model = nullptr;
        return -1;
    }

    // 5. 初始化采样器
    common_params_sampling sampling_params;
    sampling_params.temp = 0.1f;
    sampling_params.top_k = 40;
    sampling_params.top_p = 0.9f;
    g_state.smpl = common_sampler_init(g_state.model, sampling_params);

    g_state.initialized = true;
    printf("[JoyCaption] 模型加载成功\n");
    return 0;
}

/**
 * 分析图片（单轮推理）
 * @param image_path 图片路径
 * @param prompt 提示词（可选，为 NULL 使用默认）
 * @return 描述文本（静态缓冲区，不需要释放）
 */
const char* joycaption_analyze(const char* image_path, const char* prompt) {
    if (!g_state.initialized) {
        return "[错误] 模型未初始化";
    }

    // 默认提示词
    const char* default_prompt = "Describe this image in detail.";
    if (prompt == nullptr || strlen(prompt) == 0) {
        prompt = default_prompt;
    }

    // 1. 加载图片
    mtmd_bitmap* bitmap = mtmd_helper_bitmap_init_from_file(g_state.ctx_vision, image_path);
    if (bitmap == nullptr) {
        snprintf(g_result_buffer, sizeof(g_result_buffer), 
                 "[错误] 无法加载图片: %s", image_path);
        return g_result_buffer;
    }

    // 2. 构建提示词（添加 image marker）
    std::string full_prompt = mtmd_default_marker();
    full_prompt += prompt;

    // 3. 创建输入文本
    mtmd_input_text text;
    text.text = full_prompt.c_str();
    text.add_special = true;
    text.parse_special = true;

    // 4. Tokenize
    mtmd_input_chunks* chunks = mtmd_input_chunks_init();
    const mtmd_bitmap* bitmaps[] = { bitmap };
    int32_t res = mtmd_tokenize(g_state.ctx_vision, chunks, &text, bitmaps, 1);
    if (res != 0) {
        mtmd_bitmap_free(bitmap);
        mtmd_input_chunks_free(chunks);
        snprintf(g_result_buffer, sizeof(g_result_buffer), 
                 "[错误] Tokenize 失败: %d", res);
        return g_result_buffer;
    }

    // 5. Eval chunks
    llama_pos n_past = 0;
    llama_pos new_n_past;
    if (mtmd_helper_eval_chunks(g_state.ctx_vision, g_state.lctx, chunks, 
                                 n_past, 0, 2048, true, &new_n_past)) {
        mtmd_bitmap_free(bitmap);
        mtmd_input_chunks_free(chunks);
        snprintf(g_result_buffer, sizeof(g_result_buffer), 
                 "[错误] Eval 失败");
        return g_result_buffer;
    }
    n_past = new_n_past;

    // 清理输入
    mtmd_bitmap_free(bitmap);
    mtmd_input_chunks_free(chunks);

    // 6. 生成回复
    llama_tokens generated_tokens;
    llama_batch batch = llama_batch_init(1, 0, 1);
    
    for (int i = 0; i < 200; i++) {  // 最多 200 tokens
        llama_token token_id = common_sampler_sample(g_state.smpl, g_state.lctx, -1);
        generated_tokens.push_back(token_id);
        common_sampler_accept(g_state.smpl, token_id, true);

        if (llama_vocab_is_eog(g_state.vocab, token_id)) {
            break;
        }

        // 准备下一个 token
        batch_clear(batch);
        batch_add(batch, token_id, n_past++, {0}, true);
        
        if (llama_decode(g_state.lctx, batch)) {
            llama_batch_free(batch);
            snprintf(g_result_buffer, sizeof(g_result_buffer), 
                     "[错误] Decode 失败");
            return g_result_buffer;
        }
    }

    llama_batch_free(batch);

    // 7. Detokenize
    std::string result_text = common_detokenize(g_state.lctx, generated_tokens);
    
    // 复制到静态缓冲区
    strncpy(g_result_buffer, result_text.c_str(), sizeof(g_result_buffer) - 1);
    g_result_buffer[sizeof(g_result_buffer) - 1] = '\0';

    // 8. 重置状态（清理 KV cache，准备下一次推理）
    llama_memory_clear(llama_get_memory(g_state.lctx), true);
    common_sampler_reset(g_state.smpl);

    return g_result_buffer;
}

/**
 * 释放资源
 */
void joycaption_free() {
    if (g_state.smpl) {
        common_sampler_free(g_state.smpl);
        g_state.smpl = nullptr;
    }
    if (g_state.ctx_vision) {
        mtmd_free(g_state.ctx_vision);
        g_state.ctx_vision = nullptr;
    }
    if (g_state.lctx) {
        llama_free(g_state.lctx);
        g_state.lctx = nullptr;
    }
    if (g_state.model) {
        llama_model_free(g_state.model);
        g_state.model = nullptr;
    }
    g_state.vocab = nullptr;
    g_state.initialized = false;
    
    llama_backend_free();
    printf("[JoyCaption] 资源已释放\n");
}

/**
 * 检查是否已初始化
 * @return 1 已初始化，0 未初始化
 */
int joycaption_is_initialized() {
    return g_state.initialized ? 1 : 0;
}

} // extern "C"
