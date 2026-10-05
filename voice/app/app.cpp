// voice/app/app.cpp
// My Agent 统一界面：摄像头画面（人脸门控）+ 语音监听（SenseVoice）+ 状态栏
//   · 摄像头：USB + RTSP 分屏，双击全屏
//   · 人脸门控：无人脸则不出画面（黑屏），仅音频监控
//   · 音频：ALSA 采集 → VAD 断句 → SenseVoice.cpp 识别 → 转发 Master
//   · 底部状态栏：状态 / 麦克风电平 / 最近识别文本（OpenCV freetype 渲染中文）
//
// 编译: make -C voice/app
// 运行: voice/app.sh [--no-audio] [--no-face-gate] [--usb-only|--rtsp-only] [--size WxH]

#include <alsa/asoundlib.h>
#include <SDL2/SDL.h>
#include <opencv2/opencv.hpp>
#include <opencv2/freetype.hpp>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <mutex>
#include <queue>
#include <regex>
#include <string>
#include <thread>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

#include "../wake.h"

namespace {

std::atomic<bool> g_run{true};
std::mutex g_mtx;
cv::Mat g_frame, g_frame2;
std::atomic<int> g_fullscreen{0};
std::atomic<long long> g_face_seen1{0}, g_face_seen2{0};

long long now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}
void on_signal(int) { g_run = false; }

std::string env_str(const char *k, const char *def) {
    const char *v = getenv(k);
    return (v && *v) ? std::string(v) : std::string(def);
}

// ── 界面共享状态 ─────────────────────────────────────────────
struct UiState {
    std::mutex m;
    std::string status = "等待语音";
    std::string last;      // 最近识别文本
    std::string reply;     // 最近转发状态
    int level = 0;         // 0..32767
    bool speaking = false;

    void set_status(const std::string &s) { std::lock_guard<std::mutex> lk(m); status = s; }
    void set_level(int v, bool sp) { std::lock_guard<std::mutex> lk(m); level = v; speaking = sp; }
    void set_last(const std::string &t) { std::lock_guard<std::mutex> lk(m); last = t; }
    void set_reply(const std::string &t) { std::lock_guard<std::mutex> lk(m); reply = t; }
    void snapshot(std::string &s, std::string &l, std::string &r, int &lv, bool &sp) {
        std::lock_guard<std::mutex> lk(m);
        s = status; l = last; r = reply; lv = level; sp = speaking;
    }
};
UiState g_ui;

struct Config {
    // 摄像头
    int usb_index = atoi(env_str("CAM_USB_INDEX", "0").c_str());
    std::string rtsp = env_str("RTSP_URL", "");
    int win_w = atoi(env_str("CAM_W", "1280").c_str());
    int win_h = atoi(env_str("CAM_H", "800").c_str());
    bool use_usb = true, use_rtsp = true;
    bool face_gate = env_str("CAM_FACE_GATE", "1") != "0";
    int face_timeout_ms = atoi(env_str("CAM_FACE_TIMEOUT_MS", "1500").c_str());
    std::string face_cascade = env_str("CAM_FACE_CASCADE",
        "/usr/share/opencv4/haarcascades/haarcascade_frontalface_default.xml");
    // 音频
    bool audio = env_str("VOICE_AUDIO", "1") != "0";
    std::string mic_dev = env_str("VOICE_MIC_DEV", "plughw:2,0");
    std::string mic_card = env_str("VOICE_MIC_CARD", "2");
    std::string mic_gain = env_str("VOICE_MIC_GAIN", "7810");
    std::string asr_bin = env_str("SENSEVOICE_BIN", "/opt/SenseVoice.cpp/bin/sense-voice-main");
    std::string asr_model = env_str("SENSEVOICE_MODEL", "/data/models/sense-voice-small-q4_k.gguf");
    std::string lang = env_str("SENSEVOICE_LANG", "zh");
    int threads = atoi(env_str("SENSEVOICE_THREADS", "4").c_str());
    std::string agent_url = env_str("AGENT_URL", "http://localhost:4097");
    std::string operator_dir = env_str("OPERATOR_DIR", "/opt/my-agent/operator");
    bool forward = true;
    int silence_ms = atoi(env_str("VOICE_SILENCE_MS", "1200").c_str());
    int min_speech_ms = atoi(env_str("VOICE_MIN_SPEECH_MS", "300").c_str());
    std::string wake_words = env_str("VOICE_WAKE", "你好星期五,星期五"); // 唤醒词(逗号分隔)
    int active_ms = atoi(env_str("VOICE_ACTIVE_MS", "10000").c_str());   // 唤醒后持续响应窗口
    std::string ack = env_str("VOICE_ACK", "在的，老板");                 // 仅唤醒时的语音应答
};

// ── 音频工具 ─────────────────────────────────────────────────
constexpr int kSampleRate = 16000;
constexpr int kFrameLen = kSampleRate / 10; // 100ms

bool write_wav(const std::string &path, const std::vector<short> &pcm) {
    auto le32 = [](int v) { return std::string{char(v), char(v >> 8), char(v >> 16), char(v >> 24)}; };
    auto le16 = [](int v) { return std::string{char(v), char(v >> 8)}; };
    int dsz = static_cast<int>(pcm.size() * sizeof(short));
    std::string h = "RIFF" + le32(36 + dsz) + "WAVE" + "fmt " + le32(16) + le16(1) + le16(1) +
                    le32(kSampleRate) + le32(kSampleRate * 2) + le16(2) + le16(16) + "data" + le32(dsz);
    FILE *f = fopen(path.c_str(), "wb");
    if (!f) return false;
    fwrite(h.data(), 1, h.size(), f);
    fwrite(pcm.data(), 2, pcm.size(), f);
    fclose(f);
    return true;
}

std::string trim(const std::string &s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return "";
    size_t b = s.find_last_not_of(" \t\r\n");
    return s.substr(a, b - a + 1);
}

std::string transcribe(const Config &cfg, const std::string &wav) {
    std::string cmd = "'" + cfg.asr_bin + "' -m '" + cfg.asr_model + "' -t " +
                      std::to_string(cfg.threads) + " -l " + cfg.lang + " '" + wav + "' 2>/dev/null";
    FILE *p = popen(cmd.c_str(), "r");
    if (!p) return "";
    char buf[4096];
    std::string out;
    while (fgets(buf, sizeof(buf), p)) out += buf;
    pclose(p);
    static const std::regex line_pat(R"(\[[0-9.]+-[0-9.]+\]\s*(.*))");
    static const std::regex tag(R"(<\|[^|]*\|>)");
    std::string text;
    std::smatch m;
    auto begin = std::sregex_iterator(out.begin(), out.end(), line_pat);
    for (auto it = begin; it != std::sregex_iterator(); ++it) {
        std::string part = trim(std::regex_replace((*it)[1].str(), tag, ""));
        if (!part.empty()) { if (!text.empty()) text += " "; text += part; }
    }
    return trim(text);
}

std::string json_escape(const std::string &s) {
    std::string esc;
    for (char c : s) {
        switch (c) {
            case '"': esc += "\\\""; break;
            case '\\': esc += "\\\\"; break;
            case '\n': esc += "\\n"; break;
            case '\r': esc += "\\r"; break;
            case '\t': esc += "\\t"; break;
            default: esc += c;
        }
    }
    return esc;
}

bool tui_attached() {
    return system("pgrep -f 'opencode[ ]attach' >/dev/null 2>&1") == 0;
}

void forward(const Config &cfg, const std::string &text) {
    if (!tui_attached()) {
        fprintf(stderr, "[app] opencode TUI 未运行，自动拉起...\n");
        if (system("/opt/my-agent/operator/ensure_tui.sh >/dev/null 2>&1") != 0)
            fprintf(stderr, "[app] 警告: 拉起 TUI 失败，指令可能无法处理\n");
    }
    std::string body = "{\"text\": \"" + json_escape("[语音输入] " + text) + "\"}";
    std::string path = "/tmp/myagent_app_" + std::to_string(getpid()) + ".json";
    FILE *f = fopen(path.c_str(), "wb"); if (!f) return;
    fwrite(body.data(), 1, body.size(), f); fclose(f);
    std::string cmd = "sh -c '"
        "curl -s --max-time 10 -X POST -H \"Content-Type: application/json\" --data-binary @" + path +
        " \"" + cfg.agent_url + "/tui/append-prompt\" >/dev/null 2>&1;"
        "curl -s --max-time 10 -X POST -H \"Content-Type: application/json\" -d \"{}\" \"" +
        cfg.agent_url + "/tui/submit-prompt\" >/dev/null 2>&1; rm -f " + path + "' >/dev/null 2>&1";
    if (system(cmd.c_str()) == -1) fprintf(stderr, "[app] 转发启动失败\n");
    g_ui.set_reply("已转发 Master");
}

// —— 唤醒门控 / 音乐暂停 / TTS 静音 ——
long read_music_pid() {
    FILE *f = fopen("/tmp/myagent_music.pid", "r");
    if (!f) return -1;
    long pid = -1;
    if (fscanf(f, "%ld", &pid) != 1) pid = -1;
    fclose(f);
    return pid;
}
long g_music_pid = -1;
bool g_music_paused = false;
std::chrono::steady_clock::time_point g_active_until{};

bool tts_active() {
    struct stat st;
    if (stat("/tmp/myagent_tts_active", &st) != 0) return false;
    return (time(nullptr) - st.st_mtime) < 30;
}

// 命中唤醒词或处于活跃窗口才转发；放歌时唤醒即暂停、窗口结束恢复；TTS 期间静音
bool handle_text(const Config &cfg, const std::string &text) {
    if (tts_active()) {
        printf("[app] TTS 播放中，静音忽略: %s\n", text.c_str());
        g_ui.set_status("TTS 播放中");
        return false;
    }
    std::string norm = wake::normalize(text);
    std::string rest;
    bool woke = wake::strip(norm, cfg.wake_words, rest);
    auto now = std::chrono::steady_clock::now();
    bool active = now < g_active_until;
    if (!woke && !active) {
        printf("[app] 未唤醒(静默): %s\n", text.c_str());
        g_ui.set_status("未唤醒·静默");
        return false;
    }
    long mp = read_music_pid();
    if (woke && mp > 0 && kill(mp, 0) == 0 && !g_music_paused) {
        kill(mp, SIGSTOP);
        g_music_pid = mp;
        g_music_paused = true;
        printf("[app] 已暂停音乐(pid=%ld)\n", mp);
    }
    std::string cmd = woke ? rest : norm;
    if (woke && cmd.empty()) {
        printf("[app] 唤醒应答: %s\n", cfg.ack.c_str());
        std::string ackcmd = "/opt/my-agent/voice/say.sh '" + cfg.ack + "' >/dev/null 2>&1";
        int rc = system(ackcmd.c_str()); (void)rc;
        return true;
    }
    g_active_until = now + std::chrono::milliseconds(cfg.active_ms);
    printf("[app] 已唤醒 → %s\n", cmd.c_str());
    forward(cfg, cmd);
    return true;
}

// ── 摄像头线程 ───────────────────────────────────────────────
void usb_thread(int index) {
    while (g_run) {
        cv::VideoCapture cap;
        if (!cap.open(index, cv::CAP_V4L2)) {
            for (int i = 0; i < 20 && g_run; ++i) usleep(100000);
            continue;
        }
        cap.set(cv::CAP_PROP_FRAME_WIDTH, 640);
        cap.set(cv::CAP_PROP_FRAME_HEIGHT, 480);
        cap.set(cv::CAP_PROP_BUFFERSIZE, 1);
        cv::Mat f;
        while (g_run && cap.read(f)) {
            if (!f.empty()) { std::lock_guard<std::mutex> lk(g_mtx); f.copyTo(g_frame); }
            usleep(33000);
        }
        cap.release();
        if (g_run) sleep(1);
    }
}

void rtsp_thread(std::string url) {
    while (g_run) {
        cv::VideoCapture cap(url.c_str(), cv::CAP_FFMPEG);
        if (!cap.isOpened()) {
            for (int i = 0; i < 20 && g_run; ++i) usleep(100000);
            continue;
        }
        cap.set(cv::CAP_PROP_BUFFERSIZE, 1);
        cv::Mat f;
        while (g_run && cap.read(f)) {
            if (f.empty()) break;
            { std::lock_guard<std::mutex> lk(g_mtx); f.copyTo(g_frame2); }
            usleep(33000);
        }
        cap.release();
        if (g_run) sleep(1);
    }
}

bool has_face(cv::CascadeClassifier &cc, const cv::Mat &frame) {
    if (frame.empty()) return false;
    cv::Mat gray;
    cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
    cv::resize(gray, gray, cv::Size(gray.cols / 2, gray.rows / 2));
    cv::equalizeHist(gray, gray);
    std::vector<cv::Rect> faces;
    cc.detectMultiScale(gray, faces, 1.1, 4, 0, cv::Size(40, 40));
    return !faces.empty();
}

void face_thread(Config cfg) {
    cv::CascadeClassifier cc(cfg.face_cascade);
    if (cc.empty()) { fprintf(stderr, "[app] 人脸分类器加载失败，门控关闭\n"); return; }
    while (g_run) {
        cv::Mat f1, f2;
        {
            std::lock_guard<std::mutex> lk(g_mtx);
            if (!g_frame.empty()) g_frame.copyTo(f1);
            if (!g_frame2.empty()) g_frame2.copyTo(f2);
        }
        long long t = now_ms();
        if (has_face(cc, f1)) g_face_seen1 = t;
        if (has_face(cc, f2)) g_face_seen2 = t;
        for (int i = 0; i < 2 && g_run; ++i) usleep(100000);
    }
}

// ── 音频线程 ─────────────────────────────────────────────────
void audio_capture(const Config &cfg, std::queue<std::vector<short>> &q,
                   std::mutex &qm, std::condition_variable &cv) {
    snd_pcm_t *cap = nullptr;
    if (snd_pcm_open(&cap, cfg.mic_dev.c_str(), SND_PCM_STREAM_CAPTURE, 0) != 0) {
        fprintf(stderr, "[app] 无法打开采集设备 %s（音频监控关闭）\n", cfg.mic_dev.c_str());
        g_ui.set_status("麦克风打开失败");
        return;
    }
    snd_pcm_set_params(cap, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED,
                       1, kSampleRate, 1, 500000);

    std::vector<short> frame(kFrameLen), acc;
    bool speaking = false;
    int silent = 0, noise = 200;
    const int end_frames = std::max(1, cfg.silence_ms / 100);
    const int min_frames = std::max(1, cfg.min_speech_ms / 100);

    while (g_run) {
        int r = snd_pcm_readi(cap, frame.data(), kFrameLen);
        if (r < 0) { snd_pcm_prepare(cap); continue; }
        int peak = 0;
        for (int i = 0; i < r; ++i) { int a = std::abs(frame[i]); if (a > peak) peak = a; }
        int thr = std::max(500, noise * 2);
        g_ui.set_level(peak, speaking);

        if (!speaking) {
            noise = (noise * 3 + peak) / 4;
            if (peak >= thr) { speaking = true; silent = 0; acc.clear(); g_ui.set_status("录音中..."); }
            else continue;
        }
        if (peak >= thr) silent = 0; else ++silent;
        acc.insert(acc.end(), frame.begin(), frame.begin() + r);

        if (silent >= end_frames) {
            speaking = false;
            int speech_frames = static_cast<int>(acc.size()) / kFrameLen - silent;
            if (speech_frames >= min_frames) {
                { std::lock_guard<std::mutex> lk(qm); q.push(acc); }
                cv.notify_one();
            }
            acc.clear(); silent = 0;
            if (g_run) g_ui.set_status("等待语音");
        }
    }
    snd_pcm_close(cap);
}

void audio_worker(const Config &cfg, std::queue<std::vector<short>> &q,
                  std::mutex &qm, std::condition_variable &cv) {
    while (true) {
        std::vector<short> pcm;
        {
            std::unique_lock<std::mutex> lk(qm);
            cv.wait(lk, [&] { return !q.empty() || !g_run; });
            if (q.empty() && !g_run) break;
            pcm = std::move(q.front()); q.pop();
        }
        if (pcm.empty()) continue;
        g_ui.set_status("识别中...");
        std::string wav = "/tmp/myagent_app_" + std::to_string(getpid()) + ".wav";
        if (!write_wav(wav, pcm)) { g_ui.set_status("写音频失败"); continue; }
        std::string text = transcribe(cfg, wav);
        unlink(wav.c_str());
        if (text.empty()) { g_ui.set_status("未识别到内容"); continue; }
        printf("[语音输入] %s\n", text.c_str());
        fflush(stdout);
        g_ui.set_last(text);
        g_ui.set_status("已识别");
        if (cfg.forward) handle_text(cfg, text);
        if (g_run) g_ui.set_status("等待语音");
    }
}

// ── 绘制 ─────────────────────────────────────────────────────
void draw_into(cv::Mat &canvas, const cv::Mat &frame, int ox, int ow, int oy, int oh, const char *label) {
    if (frame.empty() || ow <= 0 || oh <= 0) return;
    int fw = frame.cols, fh = frame.rows;
    float sc = std::min(static_cast<float>(ow) / fw, static_cast<float>(oh) / fh);
    int dw = std::max(1, static_cast<int>(fw * sc));
    int dh = std::max(1, static_cast<int>(fh * sc));
    cv::Mat r;
    cv::resize(frame, r, cv::Size(dw, dh));
    r.copyTo(canvas(cv::Rect(ox + (ow - dw) / 2, oy + (oh - dh) / 2, dw, dh)));
    cv::putText(canvas, label, cv::Point(ox + 8, oy + 26), cv::FONT_HERSHEY_SIMPLEX, 0.6,
                cv::Scalar(200, 220, 255), 2, cv::LINE_AA);
}

} // namespace

int main(int argc, char **argv) {
    Config cfg;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--usb" && i + 1 < argc) cfg.usb_index = atoi(argv[++i]);
        else if (a == "--rtsp" && i + 1 < argc) cfg.rtsp = argv[++i];
        else if (a == "--usb-only") cfg.use_rtsp = false;
        else if (a == "--rtsp-only") cfg.use_usb = false;
        else if (a == "--no-face-gate") cfg.face_gate = false;
        else if (a == "--face-gate") cfg.face_gate = true;
        else if (a == "--no-audio") cfg.audio = false;
        else if (a == "--audio") cfg.audio = true;
        else if (a == "--no-forward") cfg.forward = false;
        else if (a == "--size" && i + 1 < argc) { int w, h; if (sscanf(argv[++i], "%dx%d", &w, &h) == 2) { cfg.win_w = w; cfg.win_h = h; } }
        else if (a == "-h" || a == "--help") {
            printf("用法: %s [--no-audio] [--no-face-gate] [--no-forward]\n", argv[0]);
            printf("       [--usb N] [--rtsp URL] [--usb-only|--rtsp-only] [--size WxH]\n");
            printf("  统一界面：摄像头画面（人脸门控）+ 语音监听（SenseVoice）+ 状态栏\n");
            return 0;
        }
    }
    if (cfg.use_rtsp && cfg.rtsp.empty()) cfg.use_rtsp = false;
    if (!cfg.use_usb && !cfg.use_rtsp && !cfg.audio) { fprintf(stderr, "[app] 无可用输入源\n"); return 1; }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    if (cfg.audio) {
        std::string mix = "amixer -c " + cfg.mic_card + " sset 'Mic' " + cfg.mic_gain + " >/dev/null 2>&1";
        if (system(mix.c_str()) != 0)
            fprintf(stderr, "[app] 提示: amixer 设置麦克风增益失败\n");
    }

    if (SDL_Init(SDL_INIT_VIDEO) < 0) { fprintf(stderr, "[app] SDL_Init 失败: %s\n", SDL_GetError()); return 1; }
    SDL_Window *win = SDL_CreateWindow("My Agent", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                       cfg.win_w, cfg.win_h, SDL_WINDOW_RESIZABLE);
    SDL_Renderer *ren = win ? SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC) : nullptr;
    if (!win || !ren) {
        fprintf(stderr, "[app] 窗口/渲染器创建失败: %s\n", SDL_GetError());
        if (ren) SDL_DestroyRenderer(ren);
        if (win) SDL_DestroyWindow(win);
        SDL_Quit();
        return 1;
    }

    // 中文渲染
    cv::Ptr<cv::freetype::FreeType2> ft = cv::freetype::createFreeType2();
    std::string font_path = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc";
    if (access(font_path.c_str(), R_OK) != 0) font_path = "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc";
    bool has_ft = false;
    try { ft->loadFontData(font_path, 0); has_ft = true; }
    catch (const std::exception &e) { fprintf(stderr, "[app] 字体加载失败: %s\n", e.what()); }
    auto text = [&](cv::Mat &img, const std::string &s, int x, int y, int sz, cv::Scalar col, int th = 1) {
        if (has_ft) ft->putText(img, s, cv::Point(x, y), sz, col, th, cv::LINE_AA, false);
    };

    SDL_Texture *tex = nullptr;
    int tw = 0, thgt = 0;

    std::thread usb, rtsp, face, acap, awork;
    if (cfg.use_usb) usb = std::thread(usb_thread, cfg.usb_index);
    if (cfg.use_rtsp) rtsp = std::thread(rtsp_thread, cfg.rtsp);
    if (cfg.face_gate) face = std::thread(face_thread, cfg);

    std::queue<std::vector<short>> aq;
    std::mutex aqm;
    std::condition_variable acv;
    if (cfg.audio) {
        acap = std::thread(audio_capture, std::cref(cfg), std::ref(aq), std::ref(aqm), std::ref(acv));
        awork = std::thread(audio_worker, std::cref(cfg), std::ref(aq), std::ref(aqm), std::ref(acv));
    }

    SDL_Event ev;
    while (g_run) {
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) g_run = false;
            else if (ev.type == SDL_KEYDOWN) {
                if (ev.key.keysym.sym == SDLK_ESCAPE || ev.key.keysym.sym == SDLK_q) {
                    if (g_fullscreen.load() != 0) g_fullscreen = 0; else g_run = false;
                }
            } else if (ev.type == SDL_MOUSEBUTTONDOWN && ev.button.clicks == 2) {
                int rw = 0, rh = 0; SDL_GetRendererOutputSize(ren, &rw, &rh);
                bool h1, h2;
                { std::lock_guard<std::mutex> lk(g_mtx); h1 = !g_frame.empty(); h2 = !g_frame2.empty(); }
                if (g_fullscreen.load() != 0) g_fullscreen = 0;
                else if (h1 && h2) g_fullscreen = (ev.button.x < rw / 2) ? 1 : 2;
                else if (h1) g_fullscreen = 1;
                else if (h2) g_fullscreen = 2;
            }
        }

        int rw = 0, rh = 0;
        SDL_GetRendererOutputSize(ren, &rw, &rh);
        if (rw <= 0 || rh <= 0) { SDL_Delay(16); continue; }
        int BH = 96;                 // 状态栏高度
        int VH = std::max(1, rh - BH);

        cv::Mat f1, f2;
        {
            std::lock_guard<std::mutex> lk(g_mtx);
            if (!g_frame.empty()) g_frame.copyTo(f1);
            if (!g_frame2.empty()) g_frame2.copyTo(f2);
        }
        long long tnow = now_ms();
        bool v1 = !f1.empty(), v2 = !f2.empty();
        if (cfg.face_gate) {
            v1 = v1 && (tnow - g_face_seen1.load() <= cfg.face_timeout_ms);
            v2 = v2 && (tnow - g_face_seen2.load() <= cfg.face_timeout_ms);
        }

        cv::Mat canvas = cv::Mat::zeros(rh, rw, CV_8UC3);
        int fs = g_fullscreen.load();
        bool drew = false;
        if (v1 && fs == 1) { draw_into(canvas, f1, 0, rw, 0, VH, "USB"); drew = true; }
        else if (v2 && fs == 2) { draw_into(canvas, f2, 0, rw, 0, VH, "RTSP"); drew = true; }
        else if (v1 && v2) {
            int half = rw / 2;
            draw_into(canvas, f1, 0, half, 0, VH, "USB");
            draw_into(canvas, f2, half, half, 0, VH, "RTSP");
            drew = true;
        } else if (v1) { draw_into(canvas, f1, 0, rw, 0, VH, "USB"); drew = true; }
        else if (v2) { draw_into(canvas, f2, 0, rw, 0, VH, "RTSP"); drew = true; }

        if (!drew) {
            std::string hint = cfg.face_gate ? "未检测到人脸 · 仅音频监控中" : "无画面";
            text(canvas, hint, rw / 2 - 210, VH / 2, 30, cv::Scalar(150, 165, 190), 1);
        }

        // 底部状态栏
        cv::rectangle(canvas, cv::Rect(0, VH, rw, BH), cv::Scalar(24, 20, 14), cv::FILLED);
        std::string st, last, rep;
        int lvl; bool spk;
        g_ui.snapshot(st, last, rep, lvl, spk);
        cv::Scalar dot = spk ? cv::Scalar(60, 200, 255) : cv::Scalar(80, 200, 120);
        cv::circle(canvas, cv::Point(20, VH + 30), 8, dot, cv::FILLED);
        text(canvas, st, 38, VH + 16, 22, cv::Scalar(230, 235, 245), 1);

        // 电平条
        int bx = 220, bw = std::min(320, rw - 500), by = VH + 20, bh = 16;
        if (bw > 40) {
            cv::rectangle(canvas, cv::Rect(bx, by, bw, bh), cv::Scalar(50, 55, 65), cv::FILLED);
            int fill = std::min(bw, lvl * bw / 12000);
            cv::Scalar c = lvl > 6000 ? cv::Scalar(60, 200, 255) : cv::Scalar(90, 190, 110);
            cv::rectangle(canvas, cv::Rect(bx, by, fill, bh), c, cv::FILLED);
        }
        if (!rep.empty()) text(canvas, rep, bx + bw + 16, VH + 16, 18, cv::Scalar(120, 150, 180), 1);
        if (!last.empty()) text(canvas, "识别: " + last, 20, VH + 58, 22, cv::Scalar(220, 225, 200), 1);

        if (!tex || tw != rw || thgt != rh) {
            if (tex) SDL_DestroyTexture(tex);
            tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_BGR24, SDL_TEXTUREACCESS_STREAMING, rw, rh);
            tw = rw; thgt = rh;
        }
        SDL_RenderClear(ren);
        if (tex) {
            SDL_UpdateTexture(tex, nullptr, canvas.data, static_cast<int>(canvas.step));
            SDL_RenderCopy(ren, tex, nullptr, nullptr);
        }
        SDL_RenderPresent(ren);
        SDL_Delay(16);
    }

    g_run = false;
    { std::lock_guard<std::mutex> lk(aqm); acv.notify_all(); }
    if (usb.joinable()) usb.join();
    if (rtsp.joinable()) rtsp.join();
    if (face.joinable()) face.join();
    if (acap.joinable()) acap.join();
    if (awork.joinable()) awork.join();
    if (tex) SDL_DestroyTexture(tex);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    printf("[app] 已退出\n");
    return 0;
}
