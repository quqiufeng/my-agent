cmake_minimum_required(VERSION 3.14)
project(wechat-ocr CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# OpenCV
find_package(OpenCV REQUIRED)

# ONNX Runtime
set(ONNX_RUNTIME_DIR "/data/venv/onnxruntime-linux-x64-gpu-1.26.0")
include_directories(${ONNX_RUNTIME_DIR}/include)
link_directories(${ONNX_RUNTIME_DIR}/lib)

# X11
find_package(X11 REQUIRED)

# ======= Shared Library (for LuaJIT FFI) =======
set(LIB_SOURCES
    lib/wechat_ocr_core.cpp
    src/screenshot.cpp
    src/ocr.cpp
)
set(LIB_HEADERS
    lib/wechat_ocr_core.h
    src/screenshot.hpp
    src/ocr.hpp
)

add_library(wechat_ocr_core SHARED ${LIB_SOURCES} ${LIB_HEADERS})
target_include_directories(wechat_ocr_core
    PRIVATE ${CMAKE_SOURCE_DIR}/lib
    PRIVATE ${CMAKE_SOURCE_DIR}/src
    PUBLIC ${OpenCV_INCLUDE_DIRS}
    PUBLIC ${X11_INCLUDE_DIR}
    PUBLIC ${ONNX_RUNTIME_DIR}/include
)
target_link_libraries(wechat_ocr_core
    ${OpenCV_LIBS}
    onnxruntime
    ${X11_LIBRARIES}
    Xext
    Xcomposite
    Xrender
    pthread
    dl
)

# Set output directory
set_target_properties(wechat_ocr_core PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/lib"
)
