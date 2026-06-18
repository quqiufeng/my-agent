#pragma once
#include <string>
#include <opencv2/core.hpp>

struct WindowRect {
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;
    bool valid = false;
};

// Find WeChat window geometry
WindowRect find_wechat_window();

// Capture a region of the screen into an OpenCV BGR mat
cv::Mat capture_screen(const WindowRect &rect);

// Detect the chat area within a full WeChat window
// Returns a sub-region that excludes title bar and input box
WindowRect detect_chat_area(const cv::Mat &full_window);

// Capture the entire screen
cv::Mat capture_full_screen();

// Find WeChat window in a full-screen image by detecting its white background
// WeChat has a distinctive white/light-gray rectangular area
WindowRect find_white_window(const cv::Mat &full_screen);

// Find WeChat window XID via xdotool (works across virtual desktops)
unsigned long find_wechat_xid();

// Capture window content using XComposite (works even if window on another desktop)
cv::Mat capture_window_xcomposite(unsigned long wid);

// Find WeChat icon in the bottom taskbar by its green color
WindowRect find_taskbar_icon(const cv::Mat &full_screen);


