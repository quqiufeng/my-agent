/**
 * Piper TTS C Wrapper
 * 将 Piper C++ API 封装为 C 接口，供 Python ctypes 调用
 * 
 * 编译:
 *   在 Piper 源码目录下:
 *   mkdir build && cd build
 *   cmake -DCMAKE_CXX_FLAGS="-fPIC" ..
 *   make
 *   
 *   然后编译 wrapper:
 *   g++ -shared -fPIC -std=c++17 \
 *     -I../src/cpp \
 *     -I. \
 *     -Ipiper-phonemize/src \
 *     -Ionnxruntime/include \
 *     ../src/cpp/piper_wrapper.cpp \
 *     src/cpp/piper.cpp \
 *     -Llib -lpiper_phonemize -lonnxruntime \
 *     -lespeak-ng \
 *     -o libpiper_tts.so \
 *     -lpthread -ldl
 */

#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#include "piper.hpp"

#define PIPER_API __attribute__((visibility("default")))

extern "C" {

// Opaque handle for voice context
typedef void* PiperVoiceHandle;

// Global config (kept alive for the lifetime of the library)
static piper::PiperConfig g_piperConfig;
static bool g_initialized = false;

/**
 * 初始化 Piper TTS 引擎
 * @param espeak_data_path eSpeak-ng 数据目录路径
 * @param tashkeel_model_path 阿拉伯语 tashkeel 模型路径（可为 NULL）
 * @return 0 成功，-1 失败
 */
PIPER_API int piper_initialize(const char* espeak_data_path,
                     const char* tashkeel_model_path) {
  try {
    if (g_initialized) {
      return 0;  // Already initialized
    }

    g_piperConfig.useESpeak = true;
    if (espeak_data_path) {
      g_piperConfig.eSpeakDataPath = espeak_data_path;
    }

    if (tashkeel_model_path) {
      g_piperConfig.useTashkeel = true;
      g_piperConfig.tashkeelModelPath = tashkeel_model_path;
    }

    piper::initialize(g_piperConfig);
    g_initialized = true;
    return 0;
  } catch (const std::exception& e) {
    return -1;
  }
}

/**
 * 加载语音模型
 * @param model_path ONNX 模型文件路径
 * @param model_config_path JSON 配置文件路径
 * @param speaker_id 说话人 ID（多说话人模型），-1 表示默认
 * @param use_cuda 是否使用 CUDA
 * @return 语音句柄，NULL 表示失败
 */
PIPER_API PiperVoiceHandle piper_load_voice(const char* model_path,
                                  const char* model_config_path,
                                  int64_t speaker_id,
                                  int use_cuda) {
  try {
    if (!g_initialized) {
      return nullptr;
    }

    auto* voice = new piper::Voice();
    std::optional<piper::SpeakerId> speakerIdOpt;
    if (speaker_id >= 0) {
      speakerIdOpt = speaker_id;
    }

    piper::loadVoice(g_piperConfig, model_path, model_config_path, *voice,
                     speakerIdOpt, use_cuda != 0);
    return voice;
  } catch (const std::exception& e) {
    return nullptr;
  }
}

/**
 * 将文本合成为 WAV 文件
 * @param voice 语音句柄
 * @param text 要合成的文本
 * @param output_path 输出 WAV 文件路径
 * @return 0 成功，-1 失败
 */
PIPER_API int piper_synthesize_to_file(PiperVoiceHandle voice,
                             const char* text,
                             const char* output_path) {
  try {
    if (!voice || !text || !output_path) {
      return -1;
    }

    auto* v = static_cast<piper::Voice*>(voice);
    piper::SynthesisResult result;

    std::ofstream audioFile(output_path, std::ios::binary);
    if (!audioFile.is_open()) {
      return -1;
    }

    piper::textToWavFile(g_piperConfig, *v, text, audioFile, result);
    audioFile.close();

    return 0;
  } catch (const std::exception& e) {
    return -1;
  }
}

/**
 * 将文本合成为音频缓冲区
 * @param voice 语音句柄
 * @param text 要合成的文本
 * @param audio_buffer 输出音频缓冲区（16-bit PCM）
 * @param buffer_size 缓冲区大小（字节）
 * @param sample_rate 输出采样率
 * @return 实际生成的音频字节数，-1 表示失败
 */
PIPER_API int piper_synthesize_to_buffer(PiperVoiceHandle voice,
                               const char* text,
                               int16_t* audio_buffer,
                               int buffer_size,
                               int* sample_rate) {
  try {
    if (!voice || !text || !audio_buffer || buffer_size <= 0) {
      return -1;
    }

    auto* v = static_cast<piper::Voice*>(voice);
    piper::SynthesisResult result;
    std::vector<int16_t> tempBuffer;

    piper::textToAudio(g_piperConfig, *v, text, tempBuffer, result,
                       []() {});

    int bytesToCopy = static_cast<int>(tempBuffer.size() * sizeof(int16_t));
    if (bytesToCopy > buffer_size) {
      bytesToCopy = buffer_size;
    }

    std::memcpy(audio_buffer, tempBuffer.data(), bytesToCopy);

    if (sample_rate) {
      *sample_rate = v->synthesisConfig.sampleRate;
    }

    return bytesToCopy;
  } catch (const std::exception& e) {
    return -1;
  }
}

/**
 * 释放语音模型
 * @param voice 语音句柄
 */
PIPER_API void piper_free_voice(PiperVoiceHandle voice) {
  if (voice) {
    delete static_cast<piper::Voice*>(voice);
  }
}

/**
 * 终止 Piper 引擎
 */
PIPER_API void piper_terminate() {
  if (g_initialized) {
    piper::terminate(g_piperConfig);
    g_initialized = false;
  }
}

} // extern "C"
