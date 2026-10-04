// voice/listen/listen.cpp
// 语音入口：麦克风常驻监听 + 自适应 VAD 断句
//   ALSA 采集 → 断句写 WAV → SenseVoice.cpp 识别 → 转发 opencode Master
// 纯 C/C++（SenseVoice 为独立 C++ 程序），无 Python 依赖。
//
// 编译: make -C voice/listen
// 运行: voice/listen.sh [--once] [--no-forward]

#include <alsa/asoundlib.h>

#include <atomic>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <queue>
#include <regex>
#include <string>
#include <thread>
#include <vector>

#include <signal.h>
#include <unistd.h>

namespace {

std::atomic<bool> g_run{true};

void on_signal(int) { g_run = false; }

std::string env_or(const char *key, const char *def) {
    const char *v = getenv(key);
    return (v && *v) ? std::string(v) : std::string(def);
}

int env_int(const char *key, int def) {
    const char *v = getenv(key);
    return (v && *v) ? atoi(v) : def;
}

struct Config {
    std::string mic_dev   = env_or("VOICE_MIC_DEV", "plughw:2,0");
    std::string mic_card  = env_or("VOICE_MIC_CARD", "2");
    std::string mic_gain  = env_or("VOICE_MIC_GAIN", "7810");
    std::string asr_bin   = env_or("SENSEVOICE_BIN", "/opt/SenseVoice.cpp/bin/sense-voice-main");
    std::string asr_model = env_or("SENSEVOICE_MODEL", "/data/models/sense-voice-small-q4_k.gguf");
    std::string lang      = env_or("SENSEVOICE_LANG", "zh");
    int threads           = env_int("SENSEVOICE_THREADS", 4);
    std::string agent_url = env_or("AGENT_URL", "http://localhost:4097");
    bool forward          = true;
    bool once             = false;
    int silence_ms        = env_int("VOICE_SILENCE_MS", 1200); // 断句静音时长
    int min_speech_ms     = env_int("VOICE_MIN_SPEECH_MS", 300);
};

constexpr int kSampleRate = 16000;
constexpr int kFrameMs    = 100;
constexpr int kFrameLen   = kSampleRate * kFrameMs / 1000; // 1600

// ── WAV 写入（16kHz mono S16_LE） ─────────────────────────────
bool write_wav(const std::string &path, const std::vector<short> &pcm) {
    auto le32 = [](int v) { return std::string{char(v), char(v >> 8), char(v >> 16), char(v >> 24)}; };
    auto le16 = [](int v) { return std::string{char(v), char(v >> 8)}; };
    int dsz = static_cast<int>(pcm.size() * sizeof(short));
    std::string h = "RIFF" + le32(36 + dsz) + "WAVE" + "fmt " + le32(16) + le16(1) + le16(1) +
                    le32(kSampleRate) + le32(kSampleRate * 2) + le16(2) + le16(16) +
                    "data" + le32(dsz);
    FILE *f = fopen(path.c_str(), "wb");
    if (!f) return false;
    fwrite(h.data(), 1, h.size(), f);
    fwrite(pcm.data(), 2, pcm.size(), f);
    fclose(f);
    return true;
}

std::string strip_tags(std::string s) {
    static const std::regex tag(R"(<\|[^|]*\|>)");
    s = std::regex_replace(s, tag, "");
    return s;
}

std::string trim(const std::string &s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return "";
    size_t b = s.find_last_not_of(" \t\r\n");
    return s.substr(a, b - a + 1);
}

// 调用 SenseVoice.cpp 识别整段 WAV，返回纯文本
std::string transcribe(const Config &cfg, const std::string &wav) {
    std::string cmd = "'" + cfg.asr_bin + "' -m '" + cfg.asr_model + "' -t " +
                      std::to_string(cfg.threads) + " -l " + cfg.lang + " '" + wav + "' 2>/dev/null";
    FILE *p = popen(cmd.c_str(), "r");
    if (!p) return "";
    char buf[4096];
    std::string out;
    while (fgets(buf, sizeof(buf), p)) out += buf;
    pclose(p);

    // 逐行解析 [start-end] text
    static const std::regex line_pat(R"(\[[0-9.]+-[0-9.]+\]\s*(.*))");
    std::string text;
    size_t pos = 0;
    while (pos < out.size()) {
        size_t nl = out.find('\n', pos);
        std::string line = out.substr(pos, nl == std::string::npos ? std::string::npos : nl - pos);
        pos = (nl == std::string::npos) ? out.size() : nl + 1;
        std::smatch m;
        if (std::regex_search(line, m, line_pat)) {
            std::string part = trim(strip_tags(m[1].str()));
            if (!part.empty()) {
                if (!text.empty()) text += " ";
                text += part;
            }
        }
    }
    return trim(text);
}

// 通过 curl 转发 [语音输入] 文本到 Master（写 JSON 文件，避免转义问题）
void forward(const Config &cfg, const std::string &text) {
    std::string json = "[语音输入] " + text;
    // JSON 转义
    std::string esc;
    for (char c : json) {
        switch (c) {
            case '"':  esc += "\\\""; break;
            case '\\': esc += "\\\\"; break;
            case '\n': esc += "\\n";  break;
            case '\r': esc += "\\r";  break;
            case '\t': esc += "\\t";  break;
            default:   esc += c;
        }
    }
    std::string body = "{\"text\": \"" + esc + "\"}";
    std::string path = "/tmp/voice_listen_" + std::to_string(getpid()) + ".json";
    FILE *f = fopen(path.c_str(), "wb");
    if (!f) return;
    fwrite(body.data(), 1, body.size(), f);
    fclose(f);

    std::string cmd = "curl -sf -X POST -H 'Content-Type: application/json' --data-binary @" +
                      path + " '" + cfg.agent_url + "/tui/append-prompt' >/dev/null 2>&1; " +
                      "curl -sf -X POST '" + cfg.agent_url + "/tui/submit-prompt' >/dev/null 2>&1";
    int rc = system(cmd.c_str());
    unlink(path.c_str());
    if (rc == 0)
        printf("[voice] 已转发: %s\n", text.c_str());
    else
        fprintf(stderr, "[voice] 转发失败（Master 未启动？）rc=%d\n", rc);
}

// 采集线程：ALSA → VAD 断句 → 入队
void capture_thread(const Config &cfg, std::queue<std::vector<short>> &q,
                    std::mutex &qm, std::condition_variable &cv) {
    snd_pcm_t *cap = nullptr;
    if (snd_pcm_open(&cap, cfg.mic_dev.c_str(), SND_PCM_STREAM_CAPTURE, 0) != 0) {
        fprintf(stderr, "[voice] 无法打开采集设备 %s\n", cfg.mic_dev.c_str());
        g_run = false;
        return;
    }
    snd_pcm_set_params(cap, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED,
                       1, kSampleRate, 1, 500000);
    printf("[voice] 采集设备: %s @%dHz\n", cfg.mic_dev.c_str(), kSampleRate);

    std::vector<short> frame(kFrameLen);
    std::vector<short> acc;
    bool speaking = false;
    int silent = 0;
    int noise = 200;
    const int end_frames = std::max(1, cfg.silence_ms / kFrameMs);
    const int min_frames = std::max(1, cfg.min_speech_ms / kFrameMs);

    while (g_run) {
        int r = snd_pcm_readi(cap, frame.data(), kFrameLen);
        if (r < 0) {
            snd_pcm_prepare(cap);
            continue;
        }
        int peak = 0;
        for (int i = 0; i < r; ++i) {
            int a = std::abs(frame[i]);
            if (a > peak) peak = a;
        }
        int thr = std::max(500, noise * 2);

        if (!speaking) {
            noise = (noise * 3 + peak) / 4;
            if (peak >= thr) {
                speaking = true;
                silent = 0;
                acc.clear();
                printf("[voice] 检测到语音 (peak=%d noise=%d thr=%d)\n", peak, noise, thr);
            } else {
                continue;
            }
        }

        if (peak >= thr) {
            silent = 0;
        } else {
            ++silent;
        }
        acc.insert(acc.end(), frame.begin(), frame.begin() + r);

        if (silent >= end_frames) {
            speaking = false;
            int speech_frames = static_cast<int>(acc.size()) / kFrameLen - silent;
            if (speech_frames >= min_frames) {
                std::lock_guard<std::mutex> lk(qm);
                q.push(acc);
                cv.notify_one();
            } else {
                printf("[voice] 片段过短，丢弃\n");
            }
            acc.clear();
            silent = 0;
        }
    }
    snd_pcm_close(cap);
}

// 工作线程：出队 → 识别 → 转发
void worker_thread(const Config &cfg, std::queue<std::vector<short>> &q,
                   std::mutex &qm, std::condition_variable &cv) {
    while (true) {
        std::vector<short> pcm;
        {
            std::unique_lock<std::mutex> lk(qm);
            cv.wait(lk, [&] { return !q.empty() || !g_run; });
            if (q.empty() && !g_run) break;
            pcm = std::move(q.front());
            q.pop();
        }
        if (pcm.empty()) continue;

        std::string wav = "/tmp/voice_listen_" + std::to_string(getpid()) + ".wav";
        if (!write_wav(wav, pcm)) {
            fprintf(stderr, "[voice] 写 WAV 失败\n");
            continue;
        }
        std::string text = transcribe(cfg, wav);
        unlink(wav.c_str());
        if (text.empty()) {
            printf("[voice] 未识别到内容\n");
            continue;
        }
        printf("[语音输入] %s\n", text.c_str());
        if (cfg.forward) forward(cfg, text);
        if (cfg.once) g_run = false;
    }
}

} // namespace

int main(int argc, char **argv) {
    Config cfg;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--once") cfg.once = true;
        else if (a == "--no-forward") cfg.forward = false;
        else if (a == "-h" || a == "--help") {
            printf("用法: %s [--once] [--no-forward]\n"
                   "  --once        识别到一句话后退出\n"
                   "  --no-forward  只打印识别结果，不转发 Master\n"
                   "环境变量: VOICE_MIC_DEV VOICE_MIC_CARD AGENT_URL SENSEVOICE_MODEL ...\n",
                   argv[0]);
            return 0;
        }
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    // 打开麦克风硬件增益，避免采集电平过低
    std::string mix = "amixer -c " + cfg.mic_card + " sset 'Mic' " + cfg.mic_gain + " >/dev/null 2>&1";
    if (system(mix.c_str()) != 0)
        fprintf(stderr, "[voice] 提示: amixer 设置麦克风增益失败，若识别不到请手动调高\n");

    printf("=== Friday 语音入口 (SenseVoice.cpp) ===\n");
    printf("识别语言: %s | 模型: %s\n", cfg.lang.c_str(), cfg.asr_model.c_str());
    printf("转发目标: %s%s\n", cfg.agent_url.c_str(), cfg.forward ? "" : " (已禁用)");
    printf("按 Ctrl+C 退出\n--------------------------------------\n");

    std::queue<std::vector<short>> q;
    std::mutex qm;
    std::condition_variable cv;
    std::thread cap(capture_thread, std::cref(cfg), std::ref(q), std::ref(qm), std::ref(cv));
    std::thread wrk(worker_thread, std::cref(cfg), std::ref(q), std::ref(qm), std::ref(cv));

    cap.join();
    {
        std::lock_guard<std::mutex> lk(qm);
        cv.notify_all();
    }
    wrk.join();
    printf("[voice] 已退出\n");
    return 0;
}
