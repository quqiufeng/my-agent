// agentkit.cpp — 桌面自动化 C++ 核心库（C ABI，供 LuaJIT FFI）
//
// 提供：屏幕区域截屏、XTest 鼠标/键盘输入、OpenCV 模板匹配、图像差分、窗口定位。
// 编译见同目录 Makefile：libagentkit.so
//
// OCR 由 libocr_simple.so（PP-OCRv4）单独提供，Lua 侧一起 FFI 调用。
// 先包含 OpenCV 的必要模块（避免 X11 宏污染其头文件），再包含 X11。
#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/keysym.h>
#include <X11/XKBlib.h>
#include <X11/extensions/XTest.h>

#include <cstring>
#include <string>
#include <vector>
#include <unistd.h>

static Display* dpy() {
    static Display* d = XOpenDisplay(nullptr);
    return d;
}

// 关闭 OpenCV 线程池：避免进程退出时后台线程与 Xlib 静态对象的析构竞争（SIGSEGV）。
static const bool _ocv_init = []() { cv::setNumThreads(1); return true; }();

// ───────────────────────── 截屏 ─────────────────────────
extern "C" int ak_capture(int x, int y, int w, int h, const char* out_png) {
    Display* d = dpy();
    if (!d || w <= 0 || h <= 0) return -1;
    XImage* img = XGetImage(d, DefaultRootWindow(d), x, y, w, h, AllPlanes, ZPixmap);
    if (!img) return -2;
    // 屏幕像素为 BGRA（小端 32/24 位）
    cv::Mat m(img->height, img->width, CV_8UC4,
              (void*)img->data, img->bytes_per_line);
    cv::Mat bgr;
    cv::cvtColor(m, bgr, cv::COLOR_BGRA2BGR);
    bool ok = cv::imwrite(out_png, bgr);
    XDestroyImage(img);
    return ok ? 0 : -3;
}

// ───────────────────────── 输入 ─────────────────────────
extern "C" int ak_move(int x, int y) {
    Display* d = dpy();
    if (!d) return -1;
    XTestFakeMotionEvent(d, -1, x, y, 0);
    XFlush(d);
    return 0;
}

extern "C" int ak_click(int x, int y) {
    Display* d = dpy();
    if (!d) return -1;
    XTestFakeMotionEvent(d, -1, x, y, 0);
    XFlush(d);
    usleep(15000);
    XTestFakeButtonEvent(d, 1, True, 0);
    XTestFakeButtonEvent(d, 1, False, 0);
    XFlush(d);
    return 0;
}

extern "C" int ak_button(int button) {
    Display* d = dpy();
    if (!d) return -1;
    XTestFakeButtonEvent(d, button, True, 0);
    XTestFakeButtonEvent(d, button, False, 0);
    XFlush(d);
    return 0;
}

static void fake_key(Display* d, KeySym ks, bool shift) {
    KeyCode kc = XKeysymToKeycode(d, ks);
    if (!kc) return;
    KeyCode shift_kc = XKeysymToKeycode(d, XK_Shift_L);
    if (shift) XTestFakeKeyEvent(d, shift_kc, True, 0);
    XTestFakeKeyEvent(d, kc, True, 0);
    XTestFakeKeyEvent(d, kc, False, 0);
    if (shift) XTestFakeKeyEvent(d, shift_kc, False, 0);
    XFlush(d);
}

// 单字节 ASCII 输入（自动处理 Shift）
static void type_ascii(Display* d, unsigned char c) {
    char buf[2] = {(char)c, 0};
    if (c == ' ') { fake_key(d, XK_space, false); return; }
    if (c == '\n') { fake_key(d, XK_Return, false); return; }
    if (c == '\t') { fake_key(d, XK_Tab, false); return; }
    KeySym ks = XStringToKeysym(buf);
    if (ks == NoSymbol) return;
    // 判断是否需要 Shift：比较该键码的 level0/level1
    KeyCode kc = XKeysymToKeycode(d, ks);
    bool shift = false;
    if (kc) {
        KeySym l0 = XkbKeycodeToKeysym(d, kc, 0, 0);
        KeySym l1 = XkbKeycodeToKeysym(d, kc, 0, 1);
        if (ks != l0 && ks == l1) shift = true;
    }
    fake_key(d, ks, shift);
    usleep(12000);
}

extern "C" int ak_type(const char* utf8) {
    Display* d = dpy();
    if (!d || !utf8) return -1;
    for (const unsigned char* p = (const unsigned char*)utf8; *p; ++p) {
        if (*p < 0x80) type_ascii(d, *p);
        // 非 ASCII（如中文）建议改用剪贴板；此处跳过
    }
    return 0;
}

// 组合键，如 "ctrl+a" / "shift+Tab" / "Return"
extern "C" int ak_key(const char* combo) {
    Display* d = dpy();
    if (!d || !combo) return -1;
    std::vector<KeyCode> mods;
    std::string s(combo);
    size_t pos = 0;
    std::string last;
    while (true) {
        size_t plus = s.find('+', pos);
        std::string tok = s.substr(pos, plus == std::string::npos ? std::string::npos : plus - pos);
        if (plus == std::string::npos) { last = tok; break; }
        // 修饰键
        std::string t = tok;
        for (auto& ch : t) ch = tolower(ch);
        KeySym mk = NoSymbol;
        if (t == "ctrl" || t == "control") mk = XK_Control_L;
        else if (t == "shift") mk = XK_Shift_L;
        else if (t == "alt") mk = XK_Alt_L;
        else if (t == "super" || t == "meta") mk = XK_Super_L;
        if (mk != NoSymbol) mods.push_back(XKeysymToKeycode(d, mk));
        pos = plus + 1;
    }
    KeySym ks = XStringToKeysym(last.c_str());
    if (ks == NoSymbol) return -2;
    KeyCode kc = XKeysymToKeycode(d, ks);
    for (auto m : mods) XTestFakeKeyEvent(d, m, True, 0);
    XTestFakeKeyEvent(d, kc, True, 0);
    XTestFakeKeyEvent(d, kc, False, 0);
    for (auto it = mods.rbegin(); it != mods.rend(); ++it)
        XTestFakeKeyEvent(d, *it, False, 0);
    XFlush(d);
    return 0;
}

// ───────────────────────── 模板匹配 ─────────────────────────
// 在 hay 中找 needle；命中返回 1（cx,cy 为 hay 内中心坐标，score 为相似度）
extern "C" int ak_match(const char* hay_png, const char* needle_png,
                        double thresh, int* cx, int* cy, double* score) {
    cv::Mat H = cv::imread(hay_png, cv::IMREAD_COLOR);
    cv::Mat N = cv::imread(needle_png, cv::IMREAD_COLOR);
    if (H.empty() || N.empty()) return -1;
    if (N.cols > H.cols || N.rows > H.rows) return -2;
    cv::Mat R;
    cv::matchTemplate(H, N, R, cv::TM_CCOEFF_NORMED);
    double mn, mx;
    cv::Point mloc;
    cv::minMaxLoc(R, &mn, &mx, nullptr, &mloc);
    if (score) *score = mx;
    if (cx) *cx = mloc.x + N.cols / 2;
    if (cy) *cy = mloc.y + N.rows / 2;
    return (mx >= thresh) ? 1 : 0;
}

// 两图平均绝对差（0..255），用于“区域是否变化”校验
extern "C" double ak_diff(const char* a_png, const char* b_png) {
    cv::Mat A = cv::imread(a_png, cv::IMREAD_GRAYSCALE);
    cv::Mat B = cv::imread(b_png, cv::IMREAD_GRAYSCALE);
    if (A.empty() || B.empty()) return -1.0;
    if (A.size() != B.size()) cv::resize(B, B, A.size());
    cv::Mat d;
    cv::absdiff(A, B, d);
    return cv::mean(d)[0];
}

// ───────────────────────── 窗口定位 ─────────────────────────
static Atom atom(Display* d, const char* name, bool only_if_exists) {
    return XInternAtom(d, name, only_if_exists ? 1 : 0);
}

static std::string window_title(Display* d, Window w) {
    Atom net_name = atom(d, "_NET_WM_NAME", 1);
    Atom utf8 = atom(d, "UTF8_STRING", 1);
    if (net_name && utf8) {
        Atom type;
        int fmt;
        unsigned long n, after;
        unsigned char* data = nullptr;
        if (XGetWindowProperty(d, w, net_name, 0, 1024, False, utf8,
                               &type, &fmt, &n, &after, &data) == Success && data) {
            std::string s((char*)data, n);
            XFree(data);
            return s;
        }
    }
    char* nm = nullptr;
    if (XFetchName(d, w, &nm) && nm) {
        std::string s(nm);
        XFree(nm);
        return s;
    }
    return "";
}

extern "C" int ak_find_window(const char* substr, int* x, int* y, int* w, int* h,
                              unsigned long* wid) {
    Display* d = dpy();
    if (!d) return -1;
    Window root = DefaultRootWindow(d);
    std::string needle(substr);
    Window best = 0;
    std::string best_title;

    // 优先：_NET_CLIENT_LIST（不惧 WM reparent）
    Atom cl = XInternAtom(d, "_NET_CLIENT_LIST", True);
    if (cl) {
        Atom type;
        int fmt;
        unsigned long n, after;
        unsigned char* data = nullptr;
        if (XGetWindowProperty(d, root, cl, 0, 8192, False, XA_WINDOW,
                               &type, &fmt, &n, &after, &data) == Success && data) {
            Window* wins = (Window*)data;
            // 取匹配中的“最后一个”（通常是最上层/最新）
            for (unsigned long i = 0; i < n; ++i) {
                std::string t = window_title(d, wins[i]);
                if (t.empty() || t.find(needle) == std::string::npos) continue;
                // 精确匹配优先，否则记录后续匹配（更上层）
                best = wins[i];
                best_title = t;
                if (t == needle) break;
            }
            XFree(data);
        }
    }

    // 兜底：递归 root 子树
    if (!best) {
        Window rroot, parent, *children = nullptr;
        unsigned int nchild = 0;
        if (XQueryTree(d, root, &rroot, &parent, &children, &nchild)) {
            for (unsigned int i = 0; i < nchild; ++i) {
                std::string t = window_title(d, children[i]);
                if (!t.empty() && t.find(needle) != std::string::npos) {
                    best = children[i];
                    break;
                }
            }
            if (children) XFree(children);
        }
    }

    if (!best) return 0;
    XWindowAttributes wa;
    if (!XGetWindowAttributes(d, best, &wa)) return 0;
    int rx, ry;
    Window child;
    XTranslateCoordinates(d, best, root, 0, 0, &rx, &ry, &child);
    if (x) *x = rx;
    if (y) *y = ry;
    if (w) *w = wa.width;
    if (h) *h = wa.height;
    if (wid) *wid = best;
    return 1;
}

extern "C" int ak_activate(unsigned long wid) {
    Display* d = dpy();
    if (!d || !wid) return -1;
    Window w = (Window)wid;
    XRaiseWindow(d, w);
    Atom active = atom(d, "_NET_ACTIVE_WINDOW", 0);
    XEvent e;
    memset(&e, 0, sizeof(e));
    e.xclient.type = ClientMessage;
    e.xclient.window = w;
    e.xclient.message_type = active;
    e.xclient.format = 32;
    e.xclient.data.l[0] = 1;
    e.xclient.data.l[1] = CurrentTime;
    XSendEvent(d, DefaultRootWindow(d), False,
               SubstructureRedirectMask | SubstructureNotifyMask, &e);
    XFlush(d);
    return 0;
}

// 把窗口移动到屏幕中央
extern "C" int ak_center(unsigned long wid) {
    Display* d = dpy();
    if (!d || !wid) return -1;
    Window w = (Window)wid;
    XWindowAttributes wa;
    if (!XGetWindowAttributes(d, w, &wa)) return -2;
    int sw = DisplayWidth(d, DefaultScreen(d));
    int sh = DisplayHeight(d, DefaultScreen(d));
    Window child;
    int rx, ry;
    XTranslateCoordinates(d, w, DefaultRootWindow(d), 0, 0, &rx, &ry, &child);
    int tx = (sw - wa.width) / 2, ty = (sh - wa.height) / 2;
    XMoveWindow(d, w, tx, ty);
    XFlush(d);
    return 0;
}
