// voice/wake.h — 唤醒词处理（供 listen.cpp / app.cpp 共用）
//   normalize: 去掉空白与常见中英文标点（保留 . - & % 等，避免破坏歌名/S.H.E）
//   strip:     在归一化文本中查找唤醒词（支持 "词1,词2"），命中则返回去掉唤醒词后的命令
#pragma once
#include <string>
#include <vector>

namespace wake {

inline std::string normalize(const std::string &s) {
    // 需要整段去掉的多字节标点（UTF-8 字节序列）
    static const std::vector<std::string> drop = {
        "\xEF\xBC\x8C", // ，
        "\xE3\x80\x82", // 。
        "\xEF\xBC\x81", // ！
        "\xEF\xBC\x9F", // ？
        "\xE3\x80\x81", // 、
        "\xEF\xBC\x9B", // ；
        "\xEF\xBC\x9A", // ：
        "\xE2\x80\x9C", // “
        "\xE2\x80\x9D", // ”
        "\xE2\x80\x98", // ‘
        "\xE2\x80\x99", // ’
        "\xEF\xBC\x88", // （
        "\xEF\xBC\x89", // ）
        "\xEF\xBD\x9E", // ～
    };
    std::string out;
    size_t i = 0;
    while (i < s.size()) {
        bool skipped = false;
        for (const auto &d : drop) {
            if (s.compare(i, d.size(), d) == 0) { i += d.size(); skipped = true; break; }
        }
        if (skipped) continue;
        unsigned char c = static_cast<unsigned char>(s[i]);
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n' ||
            c == ',' || c == '!' || c == '?' || c == ';' || c == ':' ||
            c == '\'' || c == '"' || c == '(' || c == ')' ||
            c == '[' || c == ']' || c == '{' || c == '}') {
            ++i;
            continue;
        }
        out += s[i++];
    }
    return out;
}

// 在 norm 中查找唤醒词（wake_csv 形如 "你好星期五,星期五"）。
// 命中返回 true，rest = 去掉该唤醒词后的文本（可能为空）。
inline bool strip(const std::string &norm, const std::string &wake_csv, std::string &rest) {
    size_t best_pos = std::string::npos, best_len = 0;
    size_t start = 0;
    while (start <= wake_csv.size()) {
        size_t comma = wake_csv.find(',', start);
        std::string w = wake_csv.substr(start, comma == std::string::npos ? std::string::npos : comma - start);
        if (!w.empty()) {
            size_t pos = norm.find(w);
            if (pos != std::string::npos && (best_pos == std::string::npos || pos < best_pos)) {
                best_pos = pos;
                best_len = w.size();
            }
        }
        if (comma == std::string::npos) break;
        start = comma + 1;
    }
    if (best_pos == std::string::npos) return false;
    rest = norm.substr(0, best_pos) + norm.substr(best_pos + best_len);
    return true;
}

} // namespace wake
