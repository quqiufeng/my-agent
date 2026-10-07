// voice/app/dotui.h — 点阵风格绘制工具（OpenCV）
// 风格来自 karminski-design-skills / dot-matrix-dashboard-ui（CC BY-NC-SA 4.0，
// 见 operator/tools/dotkit/NOTICE.md）。这里用 OpenCV 重新实现其点阵条/环/字体。
#pragma once
#include <opencv2/opencv.hpp>
#include <array>
#include <cctype>
#include <cmath>
#include <cstring>
#include <ctime>
#include <string>
#include <unordered_map>

namespace dotui {

// ── 调色板（OpenCV 为 BGR，值对应 #RRGGBB；中国色·霜地 浅色） ──
inline cv::Scalar bg()       { return {0xCB, 0xF0, 0xE2}; } // 霜地 #E2F0CB
inline cv::Scalar card_top() { return {0xE8, 0xF8, 0xF3}; } // 嫩菊绿 #F3F8E8
inline cv::Scalar card_bot() { return {0xD6, 0xF0, 0xE7}; } // #E7F0D6
inline cv::Scalar border()   { return {0xA6, 0xD6, 0xC4}; } // #C4D6A6
inline cv::Scalar ink()      { return {0x1C, 0x1B, 0x1D}; } // 墨色 #1D1B1C
inline cv::Scalar muted()    { return {0x4F, 0x6B, 0x5B}; } // #5B6B4F
inline cv::Scalar dim()      { return {0x7E, 0x9A, 0x8A}; } // #8A9A7E
inline cv::Scalar unlit()    { return {0xA0, 0xCB, 0xB9}; } // #B9CBA0
inline cv::Scalar faint()    { return {0xB4, 0xDA, 0xCB}; } // #CBDAB4
inline cv::Scalar accent()   { return {0x5C, 0x3C, 0x2A}; } // 黛蓝 #2A3C5C
inline cv::Scalar warn()     { return {0x16, 0x7A, 0xC7}; } // #C77A16
inline cv::Scalar crit()     { return {0x21, 0x21, 0xD9}; } // 朱砂红 #D92121
inline cv::Scalar ok()       { return {0x57, 0x8B, 0x2E}; } // 青绿 #2E8B57

inline void dot(cv::Mat &m, int x, int y, int r, const cv::Scalar &c) {
    cv::circle(m, {x, y}, std::max(0, r), c, cv::FILLED, cv::LINE_AA);
}

// 竖向渐变卡片背景（y0..y0+h）
inline void card(cv::Mat &m, int y0, int h, int label_thick = 0) {
    for (int i = 0; i < h; ++i) {
        double t = h > 1 ? static_cast<double>(i) / (h - 1) : 0.0;
        cv::Scalar top = card_top(), bot = card_bot();
        cv::Scalar c(top[0] * (1 - t) + bot[0] * t,
                     top[1] * (1 - t) + bot[1] * t,
                     top[2] * (1 - t) + bot[2] * t);
        cv::line(m, {0, y0 + i}, {m.cols, y0 + i}, c, 1, cv::LINE_8);
    }
    cv::line(m, {0, y0}, {m.cols, y0}, border(), std::max(1, label_thick), cv::LINE_8);
}

// 点阵条：x 起点、cy 中心、w 宽、value/max 比例
inline void bar(cv::Mat &m, int x, int cy, int w, double value, double max,
                const cv::Scalar &color, double size = 3.4, double pitch = 7.0) {
    if (w <= size) return;
    int count = std::max(2, static_cast<int>(std::floor((w - size) / pitch)) + 1);
    double f = max > 0 ? std::min(1.0, std::max(0.0, value / max)) : 0.0;
    int lit = static_cast<int>(std::lround(f * count));
    if (lit == 0 && value > 0) lit = 1;
    int r = std::max(1, static_cast<int>(std::lround(size / 2)));
    for (int i = 0; i < count; ++i) {
        int cx = x + r + static_cast<int>(std::lround(i * pitch));
        if (i < lit) dot(m, cx, cy, r, color);
        else dot(m, cx, cy, std::max(1, static_cast<int>(std::lround(r * 0.62))), unlit());
    }
}

// 点阵环：300° 扫掠，从 120° 起（与原 kit 一致）
inline void ring(cv::Mat &m, int cx, int cy, int outer, double value, double max,
                 const cv::Scalar &color) {
    for (int i = 0; i < 90; ++i) {
        double a = i * 4 * M_PI / 180.0;
        dot(m, cx + static_cast<int>(std::lround(outer * std::cos(a))),
            cy + static_cast<int>(std::lround(outer * std::sin(a))), 1, faint());
    }
    int radius = outer - 10, count = 56;
    double f = max > 0 ? std::min(1.0, std::max(0.0, value / max)) : 0.0;
    int lit = static_cast<int>(std::lround(f * count));
    if (lit == 0 && value > 0) lit = 1;
    int r = std::max(1, static_cast<int>(std::lround(2.2)));
    for (int i = 0; i < count; ++i) {
        double deg = 120 + 300.0 * i / (count - 1);
        double a = deg * M_PI / 180.0;
        int x = cx + static_cast<int>(std::lround(radius * std::cos(a)));
        int y = cy + static_cast<int>(std::lround(radius * std::sin(a)));
        if (i < lit) dot(m, x, y, r, color);
        else dot(m, x, y, std::max(1, r - 1), unlit());
    }
}

// ── 5x7 点阵字体（数字/字母/符号，与原 kit 相同） ───────────
inline const std::unordered_map<char, std::array<const char *, 7>> &glyphs() {
    static const std::unordered_map<char, std::array<const char *, 7>> g = {
        {'0', {"01110", "10001", "10011", "10101", "11001", "10001", "01110"}},
        {'1', {"00100", "01100", "00100", "00100", "00100", "00100", "01110"}},
        {'2', {"01110", "10001", "00001", "00010", "00100", "01000", "11111"}},
        {'3', {"11111", "00010", "00100", "00010", "00001", "10001", "01110"}},
        {'4', {"00010", "00110", "01010", "10010", "11111", "00010", "00010"}},
        {'5', {"11111", "10000", "11110", "00001", "00001", "10001", "01110"}},
        {'6', {"00110", "01000", "10000", "11110", "10001", "10001", "01110"}},
        {'7', {"11111", "00001", "00010", "00100", "01000", "01000", "01000"}},
        {'8', {"01110", "10001", "10001", "01110", "10001", "10001", "01110"}},
        {'9', {"01110", "10001", "10001", "01111", "00001", "00010", "01100"}},
        {'A', {"01110", "10001", "10001", "11111", "10001", "10001", "10001"}},
        {'B', {"11110", "10001", "10001", "11110", "10001", "10001", "11110"}},
        {'C', {"01110", "10001", "10000", "10000", "10000", "10001", "01110"}},
        {'D', {"11100", "10010", "10001", "10001", "10001", "10010", "11100"}},
        {'E', {"11111", "10000", "10000", "11110", "10000", "10000", "11111"}},
        {'F', {"11111", "10000", "10000", "11110", "10000", "10000", "10000"}},
        {'G', {"01110", "10001", "10000", "10111", "10001", "10001", "01111"}},
        {'H', {"10001", "10001", "10001", "11111", "10001", "10001", "10001"}},
        {'I', {"01110", "00100", "00100", "00100", "00100", "00100", "01110"}},
        {'J', {"00111", "00010", "00010", "00010", "00010", "10010", "01100"}},
        {'K', {"10001", "10010", "10100", "11000", "10100", "10010", "10001"}},
        {'L', {"10000", "10000", "10000", "10000", "10000", "10000", "11111"}},
        {'M', {"10001", "11011", "10101", "10101", "10001", "10001", "10001"}},
        {'N', {"10001", "10001", "11001", "10101", "10011", "10001", "10001"}},
        {'O', {"01110", "10001", "10001", "10001", "10001", "10001", "01110"}},
        {'P', {"11110", "10001", "10001", "11110", "10000", "10000", "10000"}},
        {'Q', {"01110", "10001", "10001", "10001", "10101", "10010", "01101"}},
        {'R', {"11110", "10001", "10001", "11110", "10100", "10010", "10001"}},
        {'S', {"01111", "10000", "10000", "01110", "00001", "00001", "11110"}},
        {'T', {"11111", "00100", "00100", "00100", "00100", "00100", "00100"}},
        {'U', {"10001", "10001", "10001", "10001", "10001", "10001", "01110"}},
        {'V', {"10001", "10001", "10001", "10001", "10001", "01010", "00100"}},
        {'W', {"10001", "10001", "10001", "10101", "10101", "10101", "01010"}},
        {'X', {"10001", "10001", "01010", "00100", "01010", "10001", "10001"}},
        {'Y', {"10001", "10001", "10001", "01010", "00100", "00100", "00100"}},
        {'Z', {"11111", "00001", "00010", "00100", "01000", "10000", "11111"}},
        {'%', {"11000", "11001", "00010", "00100", "01000", "10011", "00011"}},
        {'+', {"00000", "00100", "00100", "11111", "00100", "00100", "00000"}},
        {'/', {"00000", "00001", "00010", "00100", "01000", "10000", "00000"}},
        {'_', {"00000", "00000", "00000", "00000", "00000", "00000", "11111"}},
        {'-', {"000", "000", "000", "111", "000", "000", "000"}},
        {'.', {"0", "0", "0", "0", "0", "0", "1"}},
        {':', {"0", "1", "0", "0", "0", "1", "0"}},
        {' ', {"000", "000", "000", "000", "000", "000", "000"}},
    };
    return g;
}

// 点阵文字：返回绘制宽度（像素）
inline int text(cv::Mat &m, int x, int y, const std::string &s, double size,
                double gap, const cv::Scalar &color) {
    const auto &G = glyphs();
    double pitch = size + gap;
    int r = std::max(1, static_cast<int>(std::lround(size / 2)));
    int cx = x;
    for (char rc : s) {
        char ch = static_cast<char>(std::toupper(static_cast<unsigned char>(rc)));
        auto it = G.find(ch);
        const std::array<const char *, 7> *gp = it != G.end() ? &it->second : &G.at(' ');
        for (int row = 0; row < 7; ++row) {
            const char *line = (*gp)[row];
            for (int col = 0; line[col]; ++col) {
                if (line[col] == '1') {
                    int px = cx + static_cast<int>(std::lround(col * pitch)) + r;
                    int py = y + static_cast<int>(std::lround(row * pitch)) + r;
                    dot(m, px, py, r, color);
                }
            }
        }
        cx += static_cast<int>(std::lround((std::strlen((*gp)[0]) + 1) * pitch));
    }
    return cx - x;
}

inline std::string clock_now() {
    std::time_t t = std::time(nullptr);
    std::tm tm = *std::localtime(&t);
    char buf[16];
    std::strftime(buf, sizeof(buf), "%H:%M:%S", &tm);
    return buf;
}

} // namespace dotui
