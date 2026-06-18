#include "monitor.hpp"
#include <algorithm>
#include <chrono>
#include <iostream>
#include <thread>

Monitor::Monitor(const std::string &det_model_path,
                 const std::string &rec_model_path,
                 const std::string &dict_path) {
    ocr_ = std::make_unique<OCR>(det_model_path, rec_model_path, dict_path);
}

std::vector<TextBox> Monitor::capture_all_text() {
    WindowRect win = find_wechat_window();
    if (!win.valid) {
        std::cerr << "[Monitor] WeChat window not found" << std::endl;
        return {};
    }

    cv::Mat full_win = capture_screen(win);
    if (full_win.empty()) {
        std::cerr << "[Monitor] Failed to capture window" << std::endl;
        return {};
    }

    return ocr_->run(full_win);
}

std::string Monitor::filter_chat_area(const std::vector<TextBox> &boxes,
                                       const WindowRect &chat_rect) {
    std::string text;
    // Filter: keep items that are in the right-side chat panel
    // Sidebar items are to the left of chat_rect.x
    // Input box items are below chat_rect.y + chat_rect.height
    int chat_right = chat_rect.x + chat_rect.width;
    int chat_bottom = chat_rect.y + chat_rect.height;

    for (const auto &box : boxes) {
        int cx = box.bbox.x + box.bbox.width / 2;
        int cy = box.bbox.y + box.bbox.height / 2;

        bool in_chat = (cx >= chat_rect.x && cx <= chat_right &&
                        cy >= chat_rect.y && cy <= chat_bottom);

        if (in_chat) {
            if (!text.empty()) text += "\n";
            text += box.text;
        }
    }
    return text;
}

std::string Monitor::capture_and_ocr() {
    // Step 1: Find window and capture full image
    WindowRect win = find_wechat_window();
    if (!win.valid) return "";

    cv::Mat full_win = capture_screen(win);
    if (full_win.empty()) return "";

    // Step 2: Detect chat area bounds (used for filtering text positions)
    WindowRect chat_rect = detect_chat_area(full_win);
    if (!chat_rect.valid) return "";

    // Step 3: Run OCR on FULL window
    auto boxes = ocr_->run(full_win);

    // Step 4: Dynamically find the sidebar/chat boundary from text positions
    // Collect all text box center x-positions
    std::vector<int> x_positions;
    for (const auto &b : boxes) {
        int cx = b.bbox.x + b.bbox.width / 2;
        x_positions.push_back(cx);
    }

    // Sort x positions and find the largest gap (indicating sidebar/chat split)
    std::sort(x_positions.begin(), x_positions.end());
    int split_x = static_cast<int>(win.width * 0.45); // default fallback: 45%
    int max_gap = 0;
    for (size_t i = 1; i < x_positions.size(); ++i) {
        int gap = x_positions[i] - x_positions[i - 1];
        int gap_center = (x_positions[i] + x_positions[i - 1]) / 2;
        int gap_pct = gap_center * 100 / win.width;
        // Consider gaps in the plausible range (30%-60% of width)
        if (gap > max_gap && gap_center > win.width * 0.30 && gap_center < win.width * 0.60) {
            max_gap = gap;
            split_x = gap_center;
        }
    }

    // Debug: show the split point
    static bool debug_once = false;
    if (!debug_once) {
        std::cout << "[Debug] split_x=" << split_x << " (" << (split_x*100/win.width) << "%)"
                  << " total_boxes=" << boxes.size() << std::endl;
        debug_once = true;
    }

    // Step 5: Filter - keep only text boxes in the main chat panel
    // x: right of sidebar split, left of right panel edge
    // y: below title bar, above input box
    int right_limit = static_cast<int>(win.width * 0.88); // exclude right edge artifacts
    std::string text;
    for (const auto &b : boxes) {
        int cx = b.bbox.x + b.bbox.width / 2;
        int cy = b.bbox.y + b.bbox.height / 2;
        if (cx >= split_x && cx <= right_limit &&
            cy >= chat_rect.y &&
            cy <= chat_rect.y + chat_rect.height) {
            if (!text.empty()) text += "\n";
            text += b.text;
        }
    }
    return text;
}

void Monitor::run_loop(int interval_ms) {
    std::cout << "[Monitor] Starting WeChat monitoring loop..." << std::endl;
    std::cout << "[Monitor] Press Ctrl+C to stop" << std::endl;
    std::cout << "==========================================" << std::endl;

    int cycle_count = 0;
    while (true) {
        try {
            auto start = std::chrono::steady_clock::now();

            std::string current_text = capture_and_ocr();

            if (!current_text.empty() && current_text != prev_text_) {
                cycle_count++;
                if (prev_text_.empty()) {
                    std::cout << "[Initial Chat Content]" << std::endl;
                    std::cout << current_text << std::endl;
                } else {
                    // Simple diff: find the new part at the end
                    size_t common_prefix = 0;
                    size_t max_common = std::min(prev_text_.size(), current_text.size());
                    while (common_prefix < max_common &&
                           prev_text_[common_prefix] == current_text[common_prefix]) {
                        common_prefix++;
                    }

                    if (common_prefix < current_text.size()) {
                        std::string new_text = current_text.substr(common_prefix);
                        new_text.erase(0, new_text.find_first_not_of("\n"));
                        if (!new_text.empty() && new_text.size() > 3) {
                            std::cout << "[New Message] cycle=" << cycle_count << std::endl;
                            std::cout << new_text << std::endl;
                            std::cout << "---" << std::endl;
                        }
                    }
                }
                prev_text_ = current_text;
            }

            auto end = std::chrono::steady_clock::now();
            auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                end - start).count();
            int sleep_ms = std::max(1, interval_ms - static_cast<int>(elapsed));
            std::this_thread::sleep_for(std::chrono::milliseconds(sleep_ms));

        } catch (const std::exception &e) {
            std::cerr << "[Monitor] Error: " << e.what() << std::endl;
            std::this_thread::sleep_for(std::chrono::milliseconds(interval_ms));
        }
    }
}
