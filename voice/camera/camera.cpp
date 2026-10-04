// voice/camera/camera.cpp
// 摄像头窗口：SDL2 双摄分屏显示（USB + RTSP），双击全屏，ESC 退出。
// 迁自早期项目的 SDL2 双摄界面，剥离音频/ASR/Lua，仅保留画面显示。
//
// 编译: make -C voice/camera
// 运行: voice/camera.sh [--usb N] [--rtsp URL] [--usb-only|--rtsp-only] [--size WxH]
//
// 环境变量:
//   CAM_USB_INDEX   USB 摄像头索引（默认 0）
//   RTSP_URL        RTSP 地址（留空则不显示 RTSP）
//   CAM_W / CAM_H   窗口宽高（默认 1280x720）

#include <SDL2/SDL.h>

#include <opencv2/opencv.hpp>
#include <opencv2/freetype.hpp>

#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <unistd.h>

namespace {

std::atomic<bool> g_run{true};
std::mutex g_mtx;
cv::Mat g_frame;   // USB
cv::Mat g_frame2;  // RTSP
std::atomic<int> g_fullscreen{0}; // 0=分屏 1=USB 2=RTSP

// 人脸检测：记录各源最近一次检测到人脸的时间（毫秒）
std::atomic<long long> g_face_seen1{0};
std::atomic<long long> g_face_seen2{0};

long long now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

// 中文渲染（OpenCV freetype）；无字体时回退 cv::putText
cv::Ptr<cv::freetype::FreeType2> g_ft;
bool g_has_ft = false;

void text_cn(cv::Mat &img, const std::string &s, int x, int y, int sz, cv::Scalar col, int th = 1) {
    if (g_has_ft)
        g_ft->putText(img, s, cv::Point(x, y), sz, col, th, cv::LINE_AA, false);
    else
        cv::putText(img, s, cv::Point(x, y + sz), cv::FONT_HERSHEY_SIMPLEX, sz / 30.0, col, th, cv::LINE_AA);
}

int text_w(const std::string &s, int sz, int th = 1) {
    if (g_has_ft) {
        int base = 0;
        return g_ft->getTextSize(s, sz, th, &base).width;
    }
    int base = 0;
    return cv::getTextSize(s, cv::FONT_HERSHEY_SIMPLEX, sz / 30.0, th, &base).width;
}

void on_signal(int) { g_run = false; }

std::string env_str(const char *k, const char *def) {
    const char *v = getenv(k);
    return (v && *v) ? std::string(v) : std::string(def);
}

struct Config {
    int usb_index = atoi(env_str("CAM_USB_INDEX", "0").c_str());
    std::string rtsp = env_str("RTSP_URL", "");
    int win_w = atoi(env_str("CAM_W", "1280").c_str());
    int win_h = atoi(env_str("CAM_H", "720").c_str());
    bool use_usb = true;
    bool use_rtsp = true;
    bool face_gate = env_str("CAM_FACE_GATE", "1") != "0"; // 无人脸则不出画面
    int face_timeout_ms = atoi(env_str("CAM_FACE_TIMEOUT_MS", "1500").c_str());
    std::string face_cascade =
        env_str("CAM_FACE_CASCADE", "/usr/share/opencv4/haarcascades/haarcascade_frontalface_default.xml");
};

// 在单帧灰度图上跑 Haar 人脸检测
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

// 定期采样两路画面做人脸检测
void face_thread(Config cfg) {
    cv::CascadeClassifier cc(cfg.face_cascade);
    if (cc.empty()) {
        fprintf(stderr, "[camera] 人脸分类器加载失败: %s，人脸门控关闭\n", cfg.face_cascade.c_str());
        return;
    }
    printf("[camera] 人脸门控已开启（无人脸超时 %d ms 则隐藏画面）\n", cfg.face_timeout_ms);
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
        for (int i = 0; i < 2 && g_run; ++i) usleep(100000); // 200ms 一轮
    }
}

void usb_thread(int index) {
    while (g_run) {
        cv::VideoCapture cap;
        if (!cap.open(index, cv::CAP_V4L2)) {
            fprintf(stderr, "[camera] USB 摄像头 %d 打开失败，2s 后重试\n", index);
            for (int i = 0; i < 20 && g_run; ++i) usleep(100000);
            continue;
        }
        cap.set(cv::CAP_PROP_FRAME_WIDTH, 640);
        cap.set(cv::CAP_PROP_FRAME_HEIGHT, 480);
        cap.set(cv::CAP_PROP_BUFFERSIZE, 1);
        printf("[camera] USB 摄像头 %d 已打开\n", index);
        cv::Mat f;
        while (g_run && cap.read(f)) {
            if (!f.empty()) {
                std::lock_guard<std::mutex> lk(g_mtx);
                f.copyTo(g_frame);
            }
            usleep(33000);
        }
        cap.release();
        if (g_run) { fprintf(stderr, "[camera] USB 取流中断，重连...\n"); sleep(1); }
    }
}

void rtsp_thread(std::string url) {
    while (g_run) {
        cv::VideoCapture cap(url.c_str(), cv::CAP_FFMPEG);
        if (!cap.isOpened()) {
            fprintf(stderr, "[camera] RTSP 连接失败，2s 后重试\n");
            for (int i = 0; i < 20 && g_run; ++i) usleep(100000);
            continue;
        }
        cap.set(cv::CAP_PROP_BUFFERSIZE, 1);
        printf("[camera] RTSP 已连接\n");
        cv::Mat f;
        while (g_run && cap.read(f)) {
            if (f.empty()) break;
            std::lock_guard<std::mutex> lk(g_mtx);
            f.copyTo(g_frame2);
            usleep(33000);
        }
        cap.release();
        if (g_run) { fprintf(stderr, "[camera] RTSP 断流，重连...\n"); sleep(1); }
    }
}

// 把一帧缩放到目标区域并绘制角标
void draw_into(cv::Mat &canvas, const cv::Mat &frame, int ox, int ow, int H, const char *label) {
    if (frame.empty() || ow <= 0) return;
    int fw = frame.cols, fh = frame.rows;
    float sc = std::min(static_cast<float>(ow) / fw, static_cast<float>(H) / fh);
    int dw = std::max(1, static_cast<int>(fw * sc));
    int dh = std::max(1, static_cast<int>(fh * sc));
    cv::Mat r;
    cv::resize(frame, r, cv::Size(dw, dh));
    r.copyTo(canvas(cv::Rect(ox + (ow - dw) / 2, (H - dh) / 2, dw, dh)));
    cv::putText(canvas, label, cv::Point(ox + 8, 26), cv::FONT_HERSHEY_SIMPLEX, 0.6,
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
        else if (a == "--face-timeout" && i + 1 < argc) cfg.face_timeout_ms = atoi(argv[++i]);
        else if (a == "--size" && i + 1 < argc) {
            int w, h;
            if (sscanf(argv[++i], "%dx%d", &w, &h) == 2) { cfg.win_w = w; cfg.win_h = h; }
        } else if (a == "-h" || a == "--help") {
            printf("用法: %s [--usb N] [--rtsp URL] [--usb-only|--rtsp-only] [--size WxH]\n", argv[0]);
            printf("       [--face-gate|--no-face-gate] [--face-timeout MS]\n");
            printf("  人脸门控: 默认开启，检测不到人脸则不出画面，仅监控音频\n");
            printf("  双击: USB/RTSP 分屏↔全屏；ESC: 退出全屏或退出；q: 退出\n");
            return 0;
        }
    }
    if (cfg.use_rtsp && cfg.rtsp.empty()) {
        fprintf(stderr, "[camera] 未设置 RTSP_URL，仅显示 USB 摄像头\n");
        cfg.use_rtsp = false;
    }
    if (!cfg.use_usb && !cfg.use_rtsp) {
        fprintf(stderr, "[camera] 没有可用的摄像头源\n");
        return 1;
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        fprintf(stderr, "[camera] SDL_Init 失败: %s\n", SDL_GetError());
        return 1;
    }
    SDL_Window *win = SDL_CreateWindow("My Agent Camera", SDL_WINDOWPOS_CENTERED,
                                       SDL_WINDOWPOS_CENTERED, cfg.win_w, cfg.win_h,
                                       SDL_WINDOW_RESIZABLE);
    SDL_Renderer *ren = win ? SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED |
                                                        SDL_RENDERER_PRESENTVSYNC)
                            : nullptr;
    if (!win || !ren) {
        fprintf(stderr, "[camera] 创建窗口/渲染器失败: %s\n", SDL_GetError());
        if (ren) SDL_DestroyRenderer(ren);
        if (win) SDL_DestroyWindow(win);
        SDL_Quit();
        return 1;
    }

    SDL_Texture *tex = nullptr;
    int tw = 0, th = 0;

    // 中文渲染字体
    g_ft = cv::freetype::createFreeType2();
    std::string font_path = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc";
    if (access(font_path.c_str(), R_OK) != 0) font_path = "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc";
    try { g_ft->loadFontData(font_path, 0); g_has_ft = true; }
    catch (const std::exception &e) { fprintf(stderr, "[camera] 字体加载失败: %s\n", e.what()); }

    std::thread usb, rtsp, face;
    if (cfg.use_usb) usb = std::thread(usb_thread, cfg.usb_index);
    if (cfg.use_rtsp) rtsp = std::thread(rtsp_thread, cfg.rtsp);
    if (cfg.face_gate) face = std::thread(face_thread, cfg);

    SDL_Event ev;
    while (g_run) {
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) g_run = false;
            else if (ev.type == SDL_KEYDOWN) {
                if (ev.key.keysym.sym == SDLK_ESCAPE || ev.key.keysym.sym == SDLK_q) {
                    if (g_fullscreen.load() != 0)
                        g_fullscreen = 0;
                    else
                        g_run = false;
                }
            } else if (ev.type == SDL_MOUSEBUTTONDOWN && ev.button.clicks == 2) {
                int rw = 0, rh = 0;
                SDL_GetRendererOutputSize(ren, &rw, &rh);
                bool has1, has2;
                {
                    std::lock_guard<std::mutex> lk(g_mtx);
                    has1 = !g_frame.empty();
                    has2 = !g_frame2.empty();
                }
                if (g_fullscreen.load() != 0) {
                    g_fullscreen = 0;
                } else if (has1 && has2) {
                    g_fullscreen = (ev.button.x < rw / 2) ? 1 : 2;
                } else if (has1) {
                    g_fullscreen = 1;
                } else if (has2) {
                    g_fullscreen = 2;
                }
            }
        }

        int rw = 0, rh = 0;
        SDL_GetRendererOutputSize(ren, &rw, &rh);
        if (rw <= 0 || rh <= 0) { SDL_Delay(16); continue; }

        cv::Mat f1, f2;
        {
            std::lock_guard<std::mutex> lk(g_mtx);
            if (!g_frame.empty()) g_frame.copyTo(f1);
            if (!g_frame2.empty()) g_frame2.copyTo(f2);
        }

        long long tnow = now_ms();
        bool v1 = !f1.empty();
        bool v2 = !f2.empty();
        if (cfg.face_gate) {
            v1 = v1 && (tnow - g_face_seen1.load() <= cfg.face_timeout_ms);
            v2 = v2 && (tnow - g_face_seen2.load() <= cfg.face_timeout_ms);
        }

        SDL_RenderClear(ren);
        cv::Mat canvas = cv::Mat::zeros(rh, rw, CV_8UC3);
        int fs = g_fullscreen.load();
        bool drew = false;
        if (v1 && fs == 1) {
            draw_into(canvas, f1, 0, rw, rh, "USB");
            drew = true;
        } else if (v2 && fs == 2) {
            draw_into(canvas, f2, 0, rw, rh, "RTSP");
            drew = true;
        } else if (v1 && v2) {
            int half = rw / 2;
            draw_into(canvas, f1, 0, half, rh, "USB");
            draw_into(canvas, f2, half, half, rh, "RTSP");
            drew = true;
        } else if (v1) {
            draw_into(canvas, f1, 0, rw, rh, "USB");
            drew = true;
        } else if (v2) {
            draw_into(canvas, f2, 0, rw, rh, "RTSP");
            drew = true;
        }

        if (!drew) {
            // 无人脸（或画面关闭）：黑屏，提示仅音频监控
            std::string hint = cfg.face_gate ? "未检测到人脸 · 仅音频监控中" : "无画面";
            text_cn(canvas, hint, (rw - text_w(hint, 34)) / 2, rh / 2 - 17, 34, cv::Scalar(150, 165, 190), 1);
            std::string sub = "麦克风持续监听中 (voice/listen)";
            text_cn(canvas, sub, (rw - text_w(sub, 22)) / 2, rh / 2 + 44, 22, cv::Scalar(90, 105, 130), 1);
        }

        if (!tex || tw != rw || th != rh) {
            if (tex) SDL_DestroyTexture(tex);
            tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_BGR24, SDL_TEXTUREACCESS_STREAMING, rw, rh);
            tw = rw;
            th = rh;
        }
        if (tex) {
            SDL_UpdateTexture(tex, nullptr, canvas.data, static_cast<int>(canvas.step));
            SDL_RenderCopy(ren, tex, nullptr, nullptr);
        }
        SDL_RenderPresent(ren);
        SDL_Delay(16);
    }

    g_run = false;
    if (usb.joinable()) usb.join();
    if (rtsp.joinable()) rtsp.join();
    if (face.joinable()) face.join();
    if (tex) SDL_DestroyTexture(tex);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    printf("[camera] 已退出\n");
    return 0;
}
