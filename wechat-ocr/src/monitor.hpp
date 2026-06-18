#pragma once
#include <string>
#include <vector>
#include "screenshot.hpp"
#include "ocr.hpp"

class Monitor {
public:
    Monitor(const std::string &det_model_path,
            const std::string &rec_model_path,
            const std::string &dict_path);

    // OCR full window, return ALL text boxes (unfiltered)
    std::vector<TextBox> capture_all_text();

    // Filter text boxes to keep only those in the chat area
    // Returns text content of filtered boxes, newline-separated
    std::string filter_chat_area(const std::vector<TextBox> &boxes, const WindowRect &chat_rect);

    // Combined: capture full window, detect chat area, OCR, filter
    std::string capture_and_ocr();

    // Monitor loop: continuously check for new messages
    void run_loop(int interval_ms = 2000);

private:
    std::string prev_text_;
    std::unique_ptr<OCR> ocr_;
};
