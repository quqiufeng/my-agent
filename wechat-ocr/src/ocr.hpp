#pragma once
#include <string>
#include <vector>
#include <memory>
#include <opencv2/core.hpp>
#include <onnxruntime_cxx_api.h>

struct TextBox {
    cv::Rect bbox;
    std::string text;
    float confidence = 0.0f;
};

class OCR {
public:
    OCR(const std::string &det_model_path,
        const std::string &rec_model_path,
        const std::string &dict_path);
    ~OCR();

    // Run OCR on an image, return recognized text boxes
    std::vector<TextBox> run(const cv::Mat &image);

private:
    // Text detection
    cv::Mat detect_text(const cv::Mat &image);

    // Text recognition
    std::string recognize_text(const cv::Mat &image);

    // Post-process detection output to get bounding boxes
    std::vector<cv::Rect> extract_boxes(const cv::Mat &prob_map,
                                         const cv::Mat &original);

    // CTC decoder
    std::string ctc_decode(const std::vector<int> &preds, int blank_id);

private:
    // ONNX Runtime
    std::unique_ptr<Ort::Env> env_;
    std::unique_ptr<Ort::SessionOptions> session_options_;
    std::unique_ptr<Ort::Session> det_session_;
    std::unique_ptr<Ort::Session> rec_session_;
    Ort::MemoryInfo memory_info_{nullptr};

    // Character dictionary
    std::vector<std::string> char_list_;

    // Detection parameters
    float det_threshold_ = 0.3f;
    float det_box_threshold_ = 0.5f;
    float det_unclip_ratio_ = 1.6f;
    int det_max_side_len_ = 960;

    // Recognition parameters
    int rec_image_height_ = 48;
};
