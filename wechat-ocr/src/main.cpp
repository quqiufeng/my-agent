#include <iostream>
#include <csignal>
#include "monitor.hpp"

static std::unique_ptr<Monitor> g_monitor;

void signal_handler(int) {
    std::cout << "\n[Main] Shutting down..." << std::endl;
    exit(0);
}

int main(int argc, char *argv[]) {
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    // Model paths relative to executable directory
    std::string base_path = "models/";
    std::string det_model = base_path + "ch_PP-OCRv4_det_infer.onnx";
    std::string rec_model = base_path + "ch_PP-OCRv4_rec_infer.onnx";
    std::string dict_path = "ppocr_keys_v1.txt";

    // Override with command-line arguments
    if (argc >= 2) det_model = argv[1];
    if (argc >= 3) rec_model = argv[2];
    if (argc >= 4) dict_path = argv[3];

    std::cout << "=== WeChat OCR Monitor ===" << std::endl;
    std::cout << "Detection model:      " << det_model << std::endl;
    std::cout << "Recognition model:    " << rec_model << std::endl;
    std::cout << "Character dictionary: " << dict_path << std::endl;
    std::cout << std::endl;

    try {
        Monitor monitor(det_model, rec_model, dict_path);
        monitor.run_loop(3000);  // Check every 3 seconds
    } catch (const std::exception &e) {
        std::cerr << "Fatal error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
