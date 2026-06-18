#include "ocr.hpp"
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include <numeric>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>

OCR::OCR(const std::string &det_model_path,
         const std::string &rec_model_path,
         const std::string &dict_path)
    : memory_info_(Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault)) {

    // Load character dictionary
    std::ifstream dict_file(dict_path);
    if (!dict_file.is_open()) {
        throw std::runtime_error("Failed to open dictionary: " + dict_path);
    }
    std::string line;
    // PaddleOCR dict format: each line is one character
    // Model output classes: class 0 = CTC blank, classes 1..N = dict chars
    // So we store chars at index 0..N-1 and map model class c -> char_list[c-1]
    while (std::getline(dict_file, line)) {
        if (!line.empty()) {
            char_list_.push_back(line);
        }
    }
    std::cout << "[OCR] Loaded " << char_list_.size() << " characters from dict" << std::endl;

    // Initialize ONNX Runtime
    env_ = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "wechat-ocr");
    session_options_ = std::make_unique<Ort::SessionOptions>();
    session_options_->SetIntraOpNumThreads(4);
    session_options_->SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

    // Try to enable CUDA
    OrtCUDAProviderOptions cuda_options;
    cuda_options.device_id = 0;
    try {
        session_options_->AppendExecutionProvider_CUDA(cuda_options);
        std::cout << "[OCR] CUDA enabled" << std::endl;
    } catch (const std::exception &e) {
        std::cout << "[OCR] CUDA not available, using CPU: " << e.what() << std::endl;
    }

    // Load detection model
    det_session_ = std::make_unique<Ort::Session>(*env_, det_model_path.c_str(), *session_options_);
    std::cout << "[OCR] Detection model loaded: " << det_model_path << std::endl;

    // Load recognition model
    rec_session_ = std::make_unique<Ort::Session>(*env_, rec_model_path.c_str(), *session_options_);
    std::cout << "[OCR] Recognition model loaded: " << rec_model_path << std::endl;
}

OCR::~OCR() = default;

std::vector<TextBox> OCR::run(const cv::Mat &image) {
    if (image.empty()) return {};

    // Step 1: Text detection
    cv::Mat prob_map = detect_text(image);

    // Step 2: Extract bounding boxes from probability map
    std::vector<cv::Rect> boxes = extract_boxes(prob_map, image);

    // Step 3: Recognize text in each box
    std::vector<TextBox> results;
    for (size_t i = 0; i < boxes.size(); ++i) {
        cv::Mat cropped = image(boxes[i]);
        if (cropped.empty()) continue;

        std::string text = recognize_text(cropped);
        if (!text.empty()) {
            TextBox tb;
            tb.bbox = boxes[i];
            tb.text = text;
            tb.confidence = 1.0f;
            results.push_back(tb);
        }
    }

    return results;
}

// ==================== Text Detection ====================

static cv::Mat resize_and_normalize(const cv::Mat &img, int max_side_len) {
    int h = img.rows;
    int w = img.cols;
    int max_wh = std::max(w, h);

    float ratio = 1.0f;
    if (max_wh > max_side_len) {
        ratio = static_cast<float>(max_side_len) / static_cast<float>(max_wh);
    }

    int resize_h = static_cast<int>(h * ratio);
    int resize_w = static_cast<int>(w * ratio);

    // Make dimensions divisible by 32
    resize_h = std::max(32, (resize_h / 32) * 32);
    resize_w = std::max(32, (resize_w / 32) * 32);

    cv::Mat resized;
    cv::resize(img, resized, cv::Size(resize_w, resize_h));

    // Convert to float and normalize to [0,1]
    cv::Mat float_img;
    resized.convertTo(float_img, CV_32FC3, 1.0 / 255.0);

    // HWC -> CHW
    cv::Mat chw(resize_h, resize_w, CV_32FC3);
    std::vector<cv::Mat> channels(3);
    cv::split(float_img, channels);

    // Create NCHW blob (batch=1, channels=3, H, W)
    // ONNX input shape: [1, 3, H, W]
    return float_img; // Will be transposed later to CHW
}

cv::Mat OCR::detect_text(const cv::Mat &image) {
    int h = image.rows;
    int w = image.cols;
    int max_wh = std::max(w, h);

    float ratio = 1.0f;
    if (max_wh > det_max_side_len_) {
        ratio = static_cast<float>(det_max_side_len_) / static_cast<float>(max_wh);
    }

    int resize_h = static_cast<int>(h * ratio);
    int resize_w = static_cast<int>(w * ratio);
    resize_h = std::max(32, (resize_h / 32) * 32);
    resize_w = std::max(32, (resize_w / 32) * 32);

    // Resize
    cv::Mat resized;
    cv::resize(image, resized, cv::Size(resize_w, resize_h));

    // Convert to float and normalize
    cv::Mat float_img;
    resized.convertTo(float_img, CV_32FC3, 1.0 / 255.0);

    // HWC -> CHW
    std::vector<cv::Mat> channels(3);
    cv::split(float_img, channels);

    // Build input tensor
    std::vector<int64_t> input_shape = {1, 3, resize_h, resize_w};
    size_t input_size = 1 * 3 * resize_h * resize_w;
    std::vector<float> input_data(input_size);

    // Fill in CHW order
    for (int c = 0; c < 3; ++c) {
        for (int i = 0; i < resize_h; ++i) {
            for (int j = 0; j < resize_w; ++j) {
                input_data[c * resize_h * resize_w + i * resize_w + j] =
                    channels[c].at<float>(i, j);
            }
        }
    }

    Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
        memory_info_, input_data.data(), input_size,
        input_shape.data(), input_shape.size());

    // Run inference
    const char *input_names[] = {"x"};
    const char *output_names[] = {"sigmoid_0.tmp_0"};

    Ort::RunOptions run_options;
    auto output_tensors = det_session_->Run(
        run_options, input_names, &input_tensor, 1,
        output_names, 1);

    auto &output = output_tensors.front();
    auto output_info = output.GetTensorTypeAndShapeInfo();
    auto output_shape = output_info.GetShape();
    float *output_data = output.GetTensorMutableData<float>();

    // Output shape: [1, 1, H', W'] where H'=resize_h/4, W'=resize_w/4
    int out_h = static_cast<int>(output_shape[2]);
    int out_w = static_cast<int>(output_shape[3]);

    // Create probability map
    cv::Mat prob_map(out_h, out_w, CV_32FC1);
    for (int i = 0; i < out_h; ++i) {
        for (int j = 0; j < out_w; ++j) {
            prob_map.at<float>(i, j) = output_data[i * out_w + j];
        }
    }

    // Resize back to original image size
    cv::Mat prob_map_resized;
    cv::resize(prob_map, prob_map_resized, cv::Size(w, h));

    return prob_map_resized;
}

std::vector<cv::Rect> OCR::extract_boxes(const cv::Mat &prob_map,
                                          const cv::Mat &original) {
    std::vector<cv::Rect> boxes;

    if (prob_map.empty()) return boxes;

    // Threshold the probability map
    cv::Mat binary;
    cv::threshold(prob_map, binary, det_threshold_, 1.0, cv::THRESH_BINARY);
    binary.convertTo(binary, CV_8UC1, 255.0);

    // Find contours
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(binary, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

    for (const auto &contour : contours) {
        // Filter small contours
        double area = cv::contourArea(contour);
        if (area < 3.0) continue;

        // Get minimum area rectangle
        cv::RotatedRect min_rect = cv::minAreaRect(contour);
        cv::Rect bounding = min_rect.boundingRect();

        // Expand slightly (unclip)
        int expand_x = static_cast<int>(bounding.width * 0.1);
        int expand_y = static_cast<int>(bounding.height * 0.1);
        bounding.x = std::max(0, bounding.x - expand_x);
        bounding.y = std::max(0, bounding.y - expand_y);
        bounding.width = std::min(original.cols - bounding.x, bounding.width + 2 * expand_x);
        bounding.height = std::min(original.rows - bounding.y, bounding.height + 2 * expand_y);

        // Ensure minimum size
        if (bounding.width < 2 || bounding.height < 2) continue;

        boxes.push_back(bounding);
    }

    // Sort boxes by y then x (top to bottom, left to right)
    std::sort(boxes.begin(), boxes.end(), [](const cv::Rect &a, const cv::Rect &b) {
        if (std::abs(a.y - b.y) > 5) return a.y < b.y;
        return a.x < b.x;
    });

    return boxes;
}

// ==================== Text Recognition ====================

std::string OCR::recognize_text(const cv::Mat &image) {
    // Ensure 3-channel BGR input (model expects 3 channels)
    cv::Mat bgr;
    if (image.channels() == 1) {
        cv::cvtColor(image, bgr, cv::COLOR_GRAY2BGR);
    } else if (image.channels() == 4) {
        cv::cvtColor(image, bgr, cv::COLOR_BGRA2BGR);
    } else {
        bgr = image.clone();
    }

    int h = rec_image_height_;
    int w = bgr.cols * h / bgr.rows;
    w = std::max(8, w);

    // Resize to fixed height, variable width
    cv::Mat resized;
    cv::resize(bgr, resized, cv::Size(w, h));

    // Convert to float and normalize to [0,1]
    cv::Mat float_img;
    resized.convertTo(float_img, CV_32FC3, 1.0 / 255.0);

    // Split into 3 channels for NCHW format
    std::vector<cv::Mat> channels(3);
    cv::split(float_img, channels);

    // Build input tensor shape: [1, 3, 48, W]
    std::vector<int64_t> input_shape = {1, 3, h, w};
    size_t input_size = 1 * 3 * h * w;
    std::vector<float> input_data(input_size);

    for (int c = 0; c < 3; ++c) {
        for (int i = 0; i < h; ++i) {
            for (int j = 0; j < w; ++j) {
                input_data[c * h * w + i * w + j] = channels[c].at<float>(i, j);
            }
        }
    }

    Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
        memory_info_, input_data.data(), input_size,
        input_shape.data(), input_shape.size());

    // Run inference
    const char *input_names[] = {"x"};
    const char *output_names[] = {"softmax_11.tmp_0"};

    Ort::RunOptions run_options;
    auto output_tensors = rec_session_->Run(
        run_options, input_names, &input_tensor, 1,
        output_names, 1);

    auto &output = output_tensors.front();
    auto output_shape = output.GetTensorTypeAndShapeInfo().GetShape();
    float *output_data = output.GetTensorMutableData<float>();

    // Output shape: [1, seq_len, num_classes]
    int seq_len = static_cast<int>(output_shape[1]);
    int num_classes = static_cast<int>(output_shape[2]);

    // Argmax over class dimension for each time step
    std::vector<int> preds(seq_len);
    for (int t = 0; t < seq_len; ++t) {
        float *probs = output_data + t * num_classes;
        int max_idx = 0;
        float max_val = probs[0];
        for (int c = 1; c < num_classes; ++c) {
            if (probs[c] > max_val) {
                max_val = probs[c];
                max_idx = c;
            }
        }
        preds[t] = max_idx;
    }

    // CTC decode (blank = 0)
    return ctc_decode(preds, 0);
}

std::string OCR::ctc_decode(const std::vector<int> &preds, int blank_id) {
    std::string result;

    int prev = -1;
    for (size_t t = 0; t < preds.size(); ++t) {
        int cur = preds[t];
        if (cur == blank_id) {
            prev = cur;
            continue;
        }
        if (cur != prev) {
            // Model class indices: 0=blank, 1..N = dict chars at index 0..N-1
            int char_idx = cur - 1;
            if (char_idx >= 0 && char_idx < static_cast<int>(char_list_.size())) {
                result += char_list_[char_idx];
            }
            prev = cur;
        }
    }

    return result;
}
