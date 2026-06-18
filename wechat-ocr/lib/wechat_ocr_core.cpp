#include "wechat_ocr_core.h"
#include "../src/screenshot.hpp"
#include "../src/ocr.hpp"
#include <cstring>
#include <string>
#include <sstream>
#include <vector>
#include <cstdio>
#include <memory>
#include <unistd.h>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>

// Forward declarations
static bool detect_panel(cv::Mat &out_panel, int &out_x, int &out_y,
                          ocr_engine_t *engine);

// Run a shell command and capture output (used for xdotool desktop switching)
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

struct ocr_engine_t {
    std::unique_ptr<OCR> ocr;
    std::string last_error;
};

ocr_engine_t* ocr_create(const char* det_model_path,
                          const char* rec_model_path,
                          const char* dict_path) {
    auto* engine = new ocr_engine_t();
    try {
        engine->ocr = std::make_unique<OCR>(det_model_path, rec_model_path, dict_path);
        return engine;
    } catch (const std::exception& e) {
        engine->last_error = e.what();
        delete engine;
        return nullptr;
    }
}

void ocr_destroy(ocr_engine_t* engine) {
    if (engine) {
        delete engine;
    }
}

const char* ocr_last_error(ocr_engine_t* engine) {
    return engine ? engine->last_error.c_str() : "null engine";
}

void ocr_free_string(char* str) {
    free(str);
}

/*
 * Build a JSON string from OCR results with window info.
 * Format:
 * {"win":{"x":0,"y":0,"w":2560,"h":1408},
 *  "boxes":[{"x":10,"y":20,"w":100,"h":30,"text":"hello"}, ...]}
 */
static char* build_json_result(const std::vector<TextBox>& boxes,
                                int win_x, int win_y, int win_w, int win_h) {
    std::ostringstream json;
    json << "{";

    // Window info
    json << "\"win\":{";
    json << "\"x\":" << win_x << ",";
    json << "\"y\":" << win_y << ",";
    json << "\"w\":" << win_w << ",";
    json << "\"h\":" << win_h;
    json << "},";

    // Boxes array
    json << "\"boxes\":[";
    for (size_t i = 0; i < boxes.size(); ++i) {
        if (i > 0) json << ",";
        const auto& b = boxes[i];
        json << "{";
        json << "\"x\":" << b.bbox.x << ",";
        json << "\"y\":" << b.bbox.y << ",";
        json << "\"w\":" << b.bbox.width << ",";
        json << "\"h\":" << b.bbox.height << ",";
        json << "\"text\":\"";
        for (char c : b.text) {
            switch (c) {
                case '"':  json << "\\\""; break;
                case '\\': json << "\\\\"; break;
                case '\n': json << "\\n";  break;
                case '\r': json << "\\r";  break;
                case '\t': json << "\\t";  break;
                default:
                    if (static_cast<unsigned char>(c) < 0x20) {
                        // Skip control chars
                    } else {
                        json << c;
                    }
            }
        }
        json << "\"";
        json << "}";
    }
    json << "]";

    json << "}";

    std::string s = json.str();
    char* result = (char*)malloc(s.size() + 1);
    if (result) {
        memcpy(result, s.c_str(), s.size() + 1);
    }
    return result;
}

// Helper: build minimal JSON with only win info (empty boxes)
static char* make_empty_json(int x, int y, int w, int h) {
    std::string s = R"({"win":{"x":)" + std::to_string(x)
        + R"(,"y":)" + std::to_string(y)
        + R"(,"w":)" + std::to_string(w)
        + R"(,"h":)" + std::to_string(h)
        + R"(,"boxes":[]})";
    char* r = (char*)malloc(s.size() + 1);
    if (r) memcpy(r, s.c_str(), s.size() + 1);
    return r;
}

char* ocr_capture(ocr_engine_t* engine) {
    if (!engine || !engine->ocr) {
        return nullptr;
    }

    try {
        cv::Mat panel;
        int panel_abs_x = 0, panel_abs_y = 0;

        if (!detect_panel(panel, panel_abs_x, panel_abs_y, engine)) {
            return nullptr;
        }

        // 全图OCR，用时间戳定位第三列边界
        int crop_y = 35;
        int crop_h = panel.rows - 40 - 180;
        if (crop_h < 100) { crop_y = 0; crop_h = panel.rows; }

        cv::Rect chat_roi(0, crop_y, panel.cols, crop_h);
        cv::Mat chat = panel(chat_roi);

        auto boxes = engine->ocr->run(chat);

        // 找第二列右侧的文字（时间戳或短文本）定位边界
        int boundary = panel.cols * 3 / 10; // 保底30%
        std::vector<int> right_items;
        for (auto &b : boxes) {
            int cx = b.bbox.x + b.bbox.width / 2;
            // 在第二列右侧的文字：x在15%~45%之间，长度4-8字符
            if (cx > panel.cols * 0.15 && cx < panel.cols * 0.45) {
                if (b.text.size() >= 3 && b.text.size() <= 8) {
                    right_items.push_back(cx);
                }
            }
        }
        if (!right_items.empty()) {
            std::sort(right_items.begin(), right_items.end());
            boundary = right_items[right_items.size() / 2] + 40;
        }

        // 过滤：只保留第三列（boundary右侧）的文字框
        std::vector<TextBox> filtered;
        for (auto &b : boxes) {
            int cx = b.bbox.x + b.bbox.width / 2;
            if (cx >= boundary) {
                filtered.push_back(b);
                filtered.back().bbox.x -= boundary;
            }
        }

        int abs_x = panel_abs_x + boundary;
        int abs_y = panel_abs_y + crop_y;

        if (filtered.empty()) {
            return make_empty_json(abs_x, abs_y, panel.cols - boundary, crop_h);
        }

        return build_json_result(filtered, abs_x, abs_y,
                                  panel.cols - boundary, crop_h);

    } catch (const std::exception& e) {
        engine->last_error = e.what();
        return nullptr;
    }
}

// Helper: common window detection logic used by both ocr_capture and ocr_get_input_box
// Returns (panel image, panel_abs_x, panel_abs_y) or (empty, 0, 0) on failure
static bool detect_panel(cv::Mat &out_panel, int &out_x, int &out_y,
                          ocr_engine_t *engine) {
    // Always use xdotool first for consistent full-window capture
    {
        WindowRect wr = find_wechat_window();
        if (wr.valid) {
            out_panel = capture_screen(wr);
            out_x = wr.x; out_y = wr.y;
            return true;
        }
    }
    // Fallback: white detection
    {
        cv::Mat fs = capture_full_screen();
        if (!fs.empty()) {
            WindowRect wr = find_white_window(fs);
            if (wr.valid) {
                out_panel = capture_screen(wr);
                out_x = wr.x; out_y = wr.y;
                return true;
            }
        }
    }
    // Last resort: cross-desktop
    {
        unsigned long xid = find_wechat_xid();
        if (xid) {
            std::string cur = exec_cmd("xdotool get_desktop 2>/dev/null");
            cur.erase(cur.find_last_not_of(" \n\r\t") + 1);
            exec_cmd(("xdotool set_desktop_for_window "
                + std::to_string(xid) + " " + cur + " 2>/dev/null").c_str());
            usleep(200000);
            WindowRect wr = find_wechat_window();
            if (wr.valid) {
                out_panel = capture_screen(wr);
                out_x = wr.x; out_y = wr.y;
                return true;
            }
        }
    }
    if (engine) engine->last_error = "WeChat window not found on any desktop";
    return false;
}

// 全窗口OCR，不经过滤，返回所有文字框
char* ocr_capture_all(ocr_engine_t* engine) {
    if (!engine || !engine->ocr) return nullptr;
    try {
        cv::Mat panel; int px = 0, py = 0;
        if (!detect_panel(panel, px, py, engine)) return nullptr;

        cv::Rect roi(0, 35, panel.cols, panel.rows - 220);
        if (roi.height < 100) { roi.y = 0; roi.height = panel.rows; }
        auto boxes = engine->ocr->run(panel(roi));

        if (boxes.empty()) return make_empty_json(px, py + 35, panel.cols, roi.height);
        return build_json_result(boxes, px, py + 35, panel.cols, roi.height);
    } catch (const std::exception& e) {
        if (engine) engine->last_error = e.what();
        return nullptr;
    }
}

// OCR from saved image file (more reliable than live XShm capture)
char* ocr_capture_file(ocr_engine_t* engine, const char* image_path, int ox, int oy) {
    if (!engine || !engine->ocr || !image_path) return nullptr;
    try {
        cv::Mat img = cv::imread(image_path);
        if (img.empty()) {
            if (engine) engine->last_error = "cannot read image file";
            return nullptr;
        }
        cv::Rect roi(0, 35, img.cols, img.rows - 220);
        if (roi.height < 100) { roi.y = 0; roi.height = img.rows; }
        auto boxes = engine->ocr->run(img(roi));
        if (boxes.empty()) return make_empty_json(ox, oy + 35, img.cols, roi.height);
        return build_json_result(boxes, ox, oy + 35, img.cols, roi.height);
    } catch (const std::exception& e) {
        if (engine) engine->last_error = e.what();
        return nullptr;
    }
}

// 灰度转JSON
static char* make_av_json(const std::vector<cv::Rect> &avs, int ox, int oy) {
    std::string j = R"({"avatars":[)";
    for (size_t i = 0; i < avs.size(); ++i) {
        if (i > 0) j += ",";
        j += R"({"x":)" + std::to_string(ox + avs[i].x)
            + R"(,"y":)" + std::to_string(oy + avs[i].y)
            + R"(,"w":)" + std::to_string(avs[i].width)
            + R"(,"h":)" + std::to_string(avs[i].height) + R"(})";
    }
    j += "]}";
    char* r = (char*)malloc(j.size() + 1);
    if (r) memcpy(r, j.c_str(), j.size() + 1);
    return r;
}

char* ocr_detect_avatars(ocr_engine_t*) {
    try {
        WindowRect wr = find_wechat_window();
        if (!wr.valid) return nullptr;
        cv::Mat full = capture_screen(wr);
        if (full.empty()) return nullptr;

        // 第二列左侧80px（头像区域）
        int avatar_w = 80;
        cv::Mat left = full(cv::Rect(0, 60, avatar_w, full.rows - 120));

        // 转灰度
        cv::Mat gray;
        cv::cvtColor(left, gray, cv::COLOR_BGR2GRAY);

        // 边缘检测
        cv::Mat edges;
        cv::Canny(gray, edges, 30, 100, 3);

        // 找轮廓
        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(edges, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

        std::vector<cv::Rect> avatars;
        for (auto &c : contours) {
            cv::Rect r = cv::boundingRect(c);
            double area = r.area();
            double ratio = (double)r.width / r.height;
            if (area > 600 && area < 6000 && ratio > 0.6 && ratio < 1.6 && r.height > 20) {
                // 检查颜色：取区域中心5x5像素
                int cx = r.x + r.width / 2;
                int cy = r.y + r.height / 2;
                cv::Mat patch = left(cv::Rect(
                    std::max(0,cx-3), std::max(0,cy-3),
                    std::min(6, left.cols-cx+3), std::min(6, left.rows-cy+3)));
                cv::Scalar m, s;
                cv::meanStdDev(patch, m, s);
                // 有颜色：RGB通道的标准差大（不是纯灰）
                double color_var = std::abs(s[0]) + std::abs(s[1]) + std::abs(s[2]);
                if (color_var > 15) {
                    avatars.push_back(r);
                }
            }
        }

        // 去重合并
        std::vector<cv::Rect> unique;
        for (auto &r : avatars) {
            bool dup = false;
            for (auto &u : unique) {
                if (std::abs(r.x - u.x) < 10 && std::abs(r.y - u.y) < 10) {
                    dup = true; break;
                }
            }
            if (!dup) unique.push_back(r);
        }

        return make_av_json(unique, wr.x, wr.y + 60);
    } catch (...) { return nullptr; }
}

char* ocr_get_input_box(ocr_engine_t* engine) {
    if (!engine) return nullptr;
    cv::Mat panel;
    int px = 0, py = 0;
    if (!detect_panel(panel, px, py, engine)) return nullptr;

    // Input box is at bottom of the third region
    int crop_x = static_cast<int>(panel.cols * 0.30);
    int ib_x = px + crop_x + 10;
    int ib_y = py + panel.rows - 175;
    int ib_w = panel.cols - crop_x - 30;
    int ib_h = 155;

    std::string s = R"({"x":)" + std::to_string(ib_x)
        + R"(,"y":)" + std::to_string(ib_y)
        + R"(,"w":)" + std::to_string(ib_w)
        + R"(,"h":)" + std::to_string(ib_h) + R"(})";
    char* r = (char*)malloc(s.size() + 1);
    if (r) memcpy(r, s.c_str(), s.size() + 1);
    return r;
}

char* ocr_get_file_icon(ocr_engine_t*) {
    try {
        WindowRect win = find_wechat_window();
        if (!win.valid) return nullptr;
        // 第三列底部，文件图标相对位置约 (w*0.53, h*0.65)
        int fx = win.x + static_cast<int>(win.width * 0.53);
        int fy = win.y + static_cast<int>(win.height * 0.65);
        std::string s = R"({"x":)" + std::to_string(fx)
            + R"(,"y":)" + std::to_string(fy) + R"(})";
        char* r = (char*)malloc(s.size() + 1);
        if (r) memcpy(r, s.c_str(), s.size() + 1);
        return r;
    } catch (...) { return nullptr; }
}

char* ocr_find_taskbar_icon(ocr_engine_t*) {
    try {
        cv::Mat fs = capture_full_screen();
        if (fs.empty()) return nullptr;
        WindowRect icon = find_taskbar_icon(fs);
        if (!icon.valid) return nullptr;
        std::string s = R"({"x":)" + std::to_string(icon.x)
            + R"(,"y":)" + std::to_string(icon.y)
            + R"(,"w":)" + std::to_string(icon.width)
            + R"(,"h":)" + std::to_string(icon.height) + R"(})";
        char* r = (char*)malloc(s.size() + 1);
        if (r) memcpy(r, s.c_str(), s.size() + 1);
        return r;
    } catch (...) { return nullptr; }
}
