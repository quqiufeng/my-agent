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

        // Crop to chat messages area (third region, exclude icon+list+title+input)
        int crop_x = static_cast<int>(panel.cols * 0.30);
        int crop_y = 35;
        int crop_w = panel.cols - crop_x - 10;
        int crop_h = panel.rows - 40 - 180;
        if (crop_w < 100 || crop_h < 100) {
            crop_x = 0; crop_y = 0;
            crop_w = panel.cols; crop_h = panel.rows;
        }

        cv::Rect chat_roi(crop_x, crop_y, crop_w, crop_h);
        cv::Mat chat = panel(chat_roi);

        auto boxes = engine->ocr->run(chat);

        int abs_x = panel_abs_x + crop_x;
        int abs_y = panel_abs_y + crop_y;

        if (boxes.empty()) {
            return make_empty_json(abs_x, abs_y, crop_w, crop_h);
        }

        return build_json_result(boxes, abs_x, abs_y, crop_w, crop_h);

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
