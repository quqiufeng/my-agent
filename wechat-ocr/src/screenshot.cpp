#include "screenshot.hpp"
#include <cstdio>
#include <memory>
#include <cstdlib>
#include <cstring>
#include <regex>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>
#include <cstdlib>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/extensions/XShm.h>
#include <X11/extensions/Xcomposite.h>
#include <X11/extensions/Xrender.h>
#include <sys/ipc.h>
#include <sys/shm.h>

// Run a shell command and capture output
static std::string exec_cmd(const char *cmd) {
    std::string result;
    std::unique_ptr<FILE, decltype(&pclose)> pipe(popen(cmd, "r"), pclose);
    if (!pipe) return result;
    char buf[128];
    while (fgets(buf, sizeof(buf), pipe.get()) != nullptr) {
        result += buf;
    }
    return result;
}

WindowRect find_wechat_window() {
    WindowRect rect;

    // Try xdotool to find WeChat window
    std::string output = exec_cmd("xdotool search --name '微信' 2>/dev/null | head -1");
    if (output.empty()) {
        output = exec_cmd("xdotool search --class 'WeChatAppEx' 2>/dev/null | head -1");
    }
    if (output.empty()) {
        output = exec_cmd("xdotool search --class 'wechat' 2>/dev/null | head -1");
    }
    if (output.empty()) {
        output = exec_cmd("xdotool search --class 'WeChat' 2>/dev/null | head -1");
    }
    // Try wmctrl as fallback
    if (output.empty()) {
        output = exec_cmd("wmctrl -l 2>/dev/null | grep -i '微信\\|wechat' | head -1 | awk '{print $1}'");
    }

    // Trim whitespace
    output.erase(0, output.find_first_not_of(" \n\r\t"));
    output.erase(output.find_last_not_of(" \n\r\t") + 1);

    if (output.empty()) return rect;

    // Get window geometry
    std::string cmd = "xdotool getwindowgeometry " + output + " 2>/dev/null";
    std::string geo = exec_cmd(cmd.c_str());

    // Parse "Position: x,y" and "Geometry: wxh"
    std::smatch match;
    std::regex pos_re(R"(Position:\s*(\d+),(\d+))");
    std::regex size_re(R"(Geometry:\s*(\d+)x(\d+))");

    if (std::regex_search(geo, match, pos_re) && match.size() >= 3) {
        rect.x = std::stoi(match[1].str());
        rect.y = std::stoi(match[2].str());
    }
    if (std::regex_search(geo, match, size_re) && match.size() >= 3) {
        rect.width = std::stoi(match[1].str());
        rect.height = std::stoi(match[2].str());
    }

    if (rect.width > 0 && rect.height > 0) {
        rect.valid = true;
    }
    return rect;
}

cv::Mat capture_screen(const WindowRect &rect) {
    if (!rect.valid) return cv::Mat();

    // Use ImageMagick import as primary method (more reliable with GPU windows)
    {
        std::string cmd = "import -window root -crop "
            + std::to_string(rect.width) + "x" + std::to_string(rect.height)
            + "+" + std::to_string(rect.x) + "+" + std::to_string(rect.y)
            + " /tmp/wechat_import.png 2>/dev/null";
        if (system(cmd.c_str()) == 0) {
            cv::Mat img = cv::imread("/tmp/wechat_import.png");
            if (!img.empty()) return img;
        }
    }

    // Fallback: XShm
    Display *display = XOpenDisplay(nullptr);
    if (!display) return cv::Mat();

    Window root = DefaultRootWindow(display);
    Screen *screen = DefaultScreenOfDisplay(display);

    XShmSegmentInfo shm_info;
    XImage *img = XShmCreateImage(display, DefaultVisualOfScreen(screen),
                                   DefaultDepthOfScreen(screen), ZPixmap,
                                   nullptr, &shm_info, rect.width, rect.height);

    if (img) {
        shm_info.shmid = shmget(IPC_PRIVATE, img->bytes_per_line * img->height,
                                IPC_CREAT | 0777);
        if (shm_info.shmid >= 0) {
            shm_info.shmaddr = img->data = (char *)shmat(shm_info.shmid, nullptr, 0);
            if (img->data != (char *)-1) {
                shm_info.readOnly = False;
                if (XShmAttach(display, &shm_info) &&
                    XShmGetImage(display, root, img, rect.x, rect.y, AllPlanes)) {
                    cv::Mat mat(rect.height, rect.width, CV_8UC4);
                    memcpy(mat.data, img->data, img->bytes_per_line * img->height);
                    XShmDetach(display, &shm_info);
                    XDestroyImage(img);
                    shmdt(shm_info.shmaddr);
                    shmctl(shm_info.shmid, IPC_RMID, nullptr);
                    XCloseDisplay(display);
                    cv::Mat bgr;
                    cv::cvtColor(mat, bgr, cv::COLOR_RGBA2BGR);
                    return bgr;
                }
            }
            XShmDetach(display, &shm_info);
            shmdt(shm_info.shmaddr);
            shmctl(shm_info.shmid, IPC_RMID, nullptr);
        }
        XDestroyImage(img);
    }

    XCloseDisplay(display);
    return cv::Mat();
}

// Find WeChat window XID via xdotool (works across virtual desktops)
unsigned long find_wechat_xid() {
    std::string output = exec_cmd("xdotool search --name '微信' 2>/dev/null | head -1");
    if (output.empty()) output = exec_cmd("xdotool search --class 'WeChatAppEx' 2>/dev/null | head -1");
    if (output.empty()) output = exec_cmd("xdotool search --class 'wechat' 2>/dev/null | head -1");
    if (output.empty()) output = exec_cmd("xdotool search --class 'WeChat' 2>/dev/null | head -1");
    if (output.empty()) {
        output = exec_cmd("wmctrl -l 2>/dev/null | grep -i '微信\\|wechat' | head -1 | awk '{print $1}'");
    }
    if (output.empty()) return 0;
    try { return std::stoul(output); } catch (...) { return 0; }
}

// Capture window content using XComposite (works even if window is on another desktop)
cv::Mat capture_window_xcomposite(unsigned long wid) {
    if (!wid) return cv::Mat();

    Display *d = XOpenDisplay(nullptr);
    if (!d) return cv::Mat();

    // Get window geometry first
    XWindowAttributes wa;
    if (!XGetWindowAttributes(d, wid, &wa)) {
        XCloseDisplay(d);
        return cv::Mat();
    }

    int w = wa.width;
    int h = wa.height;
    if (w <= 0 || h <= 0) {
        XCloseDisplay(d);
        return cv::Mat();
    }

    // Use XComposite to get the window's backing pixmap
    Pixmap pix = XCompositeNameWindowPixmap(d, wid);
    if (!pix) {
        XCloseDisplay(d);
        return cv::Mat();
    }

    // Read the pixmap content using XShmGetImage
    XShmSegmentInfo shm;
    XImage *img = XShmCreateImage(d, DefaultVisualOfScreen(DefaultScreenOfDisplay(d)),
                                   DefaultDepthOfScreen(DefaultScreenOfDisplay(d)),
                                   ZPixmap, nullptr, &shm, w, h);
    cv::Mat result;
    if (img) {
        shm.shmid = shmget(IPC_PRIVATE, img->bytes_per_line * img->height,
                           IPC_CREAT | 0777);
        if (shm.shmid >= 0) {
            shm.shmaddr = img->data = (char*)shmat(shm.shmid, nullptr, 0);
            if (img->data != (char*)-1) {
                shm.readOnly = False;
                if (XShmAttach(d, &shm) &&
                    XShmGetImage(d, pix, img, 0, 0, AllPlanes)) {
                    cv::Mat mat(h, w, CV_8UC4);
                    memcpy(mat.data, img->data, img->bytes_per_line * h);
                    cv::cvtColor(mat, result, cv::COLOR_RGBA2BGR);
                }
                XShmDetach(d, &shm);
                shmdt(shm.shmaddr);
                shmctl(shm.shmid, IPC_RMID, nullptr);
            } else {
                shmctl(shm.shmid, IPC_RMID, nullptr);
            }
        }
        XDestroyImage(img);
    }

    XFreePixmap(d, pix);
    XCloseDisplay(d);
    return result;
}

WindowRect detect_chat_area(const cv::Mat &full_window) {
    WindowRect rect;
    if (full_window.empty()) return rect;

    int h = full_window.rows;
    int w = full_window.cols;

    // WeChat native layout:
    // - Title bar: top ~40px
    // - Left sidebar (chat list): ~1/4 of width
    //   In the sidebar there are: search bar, chat list items
    // - Right side: current chat messages (3/4 of width)
    // - Bottom: input box ~150-200px

    cv::Mat gray;
    cv::cvtColor(full_window, gray, cv::COLOR_BGR2GRAY);

    // === TOP BOUNDARY: find title bar bottom ===
    int top_boundary = 45; // default
    for (int y = 15; y < std::min(70, h - 100); y += 1) {
        cv::Mat row = gray.row(y);
        cv::Scalar mean, stddev;
        cv::meanStdDev(row, mean, stddev);
        // Title bar typically has low variance and mid-range value
        // Content area starts when variance jumps
        if (mean[0] > 200 || stddev[0] > 30) {
            top_boundary = y;
            break;
        }
    }

    // === BOTTOM BOUNDARY: find input box top ===
    int bottom_boundary = h - 180; // default input area
    for (int y = h - 40; y > h / 2; y -= 1) {
        cv::Mat row = gray.row(y);
        cv::Scalar mean, stddev;
        cv::meanStdDev(row, mean, stddev);
        // Input box bottom border is usually a thin line
        if (stddev[0] > 30 && mean[0] < 180) {
            // We found a row with significant variation (border line)
            // The input box itself (above the border) is uniform white
            // Check if the row above is more uniform
            cv::Mat row_above = gray.row(y - 3);
            cv::Scalar m_a, s_a;
            cv::meanStdDev(row_above, m_a, s_a);
            if (s_a[0] < 10 && m_a[0] > 200) {
                bottom_boundary = y - 3;
                break;
            }
        }
    }

    // Safety
    top_boundary = std::max(30, std::min(top_boundary, 65));
    bottom_boundary = std::max(top_boundary + 150, std::min(bottom_boundary - 5, h - 50));

    // === LEFT BOUNDARY: exclude sidebar ===
    // WeChat sidebar text extends to ~36-40% of width on large windows.
    // The actual chat message panel starts at about 45-50% of width.
    // Use 42% as the left margin to filter out sidebar text safely.
    int left_margin;
    {
        // Find the rightmost sidebar text by detecting the large gap
        // between sidebar items and chat messages
        int mid_scan_y = std::min(h / 2, bottom_boundary - 100);
        // Look for a column that's all-white (no text) indicating the gap
        // between sidebar and chat area
        int best_gap = static_cast<int>(w * 0.42);
        int max_white_run = 0;
        for (int x = static_cast<int>(w * 0.35); x < static_cast<int>(w * 0.55); ++x) {
            cv::Mat col = gray.col(x);
            cv::Scalar mean, stddev;
            cv::meanStdDev(col.rowRange(top_boundary, bottom_boundary), mean, stddev);
            // A column with high mean (>230) and low stddev (<15) is likely
            // a blank gap between panels
            if (mean[0] > 230 && stddev[0] < 15) {
                int white_run = 1;
                for (int x2 = x + 1; x2 < std::min(w - 1, x + 50); ++x2) {
                    cv::Mat col2 = gray.col(x2);
                    cv::Scalar m2, s2;
                    cv::meanStdDev(col2.rowRange(top_boundary, bottom_boundary), m2, s2);
                    if (m2[0] > 230 && s2[0] < 15) white_run++;
                    else break;
                }
                if (white_run > max_white_run) {
                    max_white_run = white_run;
                    best_gap = x + white_run / 2;
                }
                x += white_run;
            }
        }
        left_margin = best_gap;
    }

    // === RIGHT BOUNDARY: minor right margin ===
    int right_margin = w - 10;

    rect.x = left_margin;
    rect.y = top_boundary;
    rect.width = std::max(200, right_margin - left_margin);
    rect.height = std::max(200, bottom_boundary - top_boundary);
    rect.valid = true;
    return rect;
}

cv::Mat capture_full_screen() {
    Display *display = XOpenDisplay(nullptr);
    if (!display) return cv::Mat();

    Screen *screen = DefaultScreenOfDisplay(display);
    int w = screen->width;
    int h = screen->height;
    XCloseDisplay(display);

    WindowRect full{0, 0, w, h, true};
    return capture_screen(full);
}

WindowRect find_white_window(const cv::Mat &full_screen) {
    WindowRect rect;
    if (full_screen.empty()) return rect;

    int h = full_screen.rows;
    int w = full_screen.cols;

    cv::Mat gray;
    cv::cvtColor(full_screen, gray, cv::COLOR_BGR2GRAY);

    // Step 1: Edge detection to find window borders
    cv::Mat edges;
    cv::Canny(gray, edges, 30, 100, 3);

    // Step 2: Dilate edges to connect nearby boundary segments
    cv::Mat dilated;
    cv::dilate(edges, dilated, cv::Mat(), cv::Point(-1, -1), 2);

    // Step 3: Find contours on edge image
    std::vector<std::vector<cv::Point>> contours;
    std::vector<cv::Vec4i> hierarchy;
    cv::findContours(dilated, contours, hierarchy,
                     cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

    double max_area = 0;
    cv::Rect best_rect;
    double screen_area = w * h;

    for (size_t i = 0; i < contours.size(); ++i) {
        // Approximate contour to polygon
        std::vector<cv::Point> approx;
        double epsilon = cv::arcLength(contours[i], true) * 0.02;
        cv::approxPolyDP(contours[i], approx, epsilon, true);

        // WeChat should have 4 corners (rectangle)
        if (approx.size() < 4 || approx.size() > 8) continue;

        cv::Rect bounds = cv::boundingRect(contours[i]);
        double area = bounds.area();
        if (area < screen_area * 0.05 || area < max_area) continue;

        double wh_ratio = static_cast<double>(bounds.width) / bounds.height;
        if (wh_ratio < 0.5 || wh_ratio > 3.0) continue;

        // Check interior: must be mostly white/light gray
        cv::Mat interior = gray(bounds);
        cv::Scalar mean, stddev;
        cv::meanStdDev(interior, mean, stddev);

        // WeChat has a bright interior (mean > 200) with some variation
        if (mean[0] > 180 && stddev[0] < 60) {
            max_area = area;
            best_rect = bounds;
        }
    }

    // If edge detection didn't find it, fall back to threshold-based approach
    if (max_area == 0) {
        cv::Mat white_mask;
        cv::threshold(gray, white_mask, 200, 255, cv::THRESH_BINARY);
        cv::findContours(white_mask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

        for (const auto &contour : contours) {
            cv::Rect bounds = cv::boundingRect(contour);
            double area = bounds.area();
            if (area < screen_area * 0.05 || area < max_area) continue;

            double wh_ratio = static_cast<double>(bounds.width) / bounds.height;
            if (wh_ratio < 0.5 || wh_ratio > 3.0) continue;

            cv::Mat roi = white_mask(bounds);
            double white_pct = static_cast<double>(cv::countNonZero(roi)) / (bounds.width * bounds.height);
            if (white_pct > 0.70) {
                cv::Rect inner = bounds;
                inner.x += 5;
                inner.y += 35;
                inner.width -= 10;
                inner.height -= 40;
                if (inner.width > 0 && inner.height > 0) {
                    cv::Mat inner_roi = gray(inner);
                    cv::Scalar im, is;
                    cv::meanStdDev(inner_roi, im, is);
                    if (im[0] > 220 && is[0] < 30) {
                        max_area = area;
                        best_rect = bounds;
                    }
                }
            }
        }
    }

    if (max_area > 0) {
        rect.x = std::max(0, best_rect.x - 2);
        rect.y = std::max(0, best_rect.y - 2);
        rect.width = std::min(w - rect.x, best_rect.width + 4);
        rect.height = std::min(h - rect.y, best_rect.height + 4);
        rect.valid = true;
    }

    return rect;
}

// Find WeChat icon in the bottom taskbar by its green color.
// WeChat icon is a small green icon on the far right of the taskbar.
WindowRect find_taskbar_icon(const cv::Mat &full_screen) {
    WindowRect rect;
    if (full_screen.empty()) return rect;

    int h = full_screen.rows;
    int w = full_screen.cols;

    // Taskbar is at the bottom ~60px; WeChat icon is on the far right
    int tb_h = std::min(60, h);
    int tb_y = h - tb_h;

    // Only scan the right half of the taskbar (system tray area)
    int scan_start_x = w / 2;
    cv::Mat taskbar = full_screen(cv::Rect(scan_start_x, tb_y, w - scan_start_x, tb_h));

    cv::Mat hsv;
    cv::cvtColor(taskbar, hsv, cv::COLOR_BGR2HSV);

    // WeChat green: H 100-150, S > 80, V > 80
    cv::Mat mask;
    cv::inRange(hsv,
                cv::Scalar(100, 80, 80),
                cv::Scalar(150, 255, 255),
                mask);

    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3));
    cv::morphologyEx(mask, mask, cv::MORPH_CLOSE, kernel);
    cv::morphologyEx(mask, mask, cv::MORPH_OPEN, kernel);

    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(mask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

    // Score candidates: prefer rightmost + proper size
    double best_score = 0;
    cv::Rect best;

    for (const auto &c : contours) {
        cv::Rect b = cv::boundingRect(c);
        double area = b.area();
        if (area < 80 || area > 4000) continue;
        double ratio = static_cast<double>(b.width) / b.height;
        if (ratio < 0.4 || ratio > 2.5) continue;

        // Score: prefer icons further right and with typical icon area
        double score = area + (w - (scan_start_x + b.x + b.width / 2)) * 0.5;
        if (score > best_score) {
            best_score = score;
            best = b;
        }
    }

    if (best_score > 0) {
        rect.x = scan_start_x + best.x;
        rect.y = tb_y + best.y;
        rect.width = best.width;
        rect.height = best.height;
        rect.valid = true;
    }

    return rect;
}
