#!/bin/bash
set -e

LLAMA_DIR=/opt/llama.cpp
BUILD_DIR=$LLAMA_DIR/build

g++ -shared -fPIC -std=c++17 \
    -I$LLAMA_DIR -I$LLAMA_DIR/include -I$LLAMA_DIR/common \
    -I$LLAMA_DIR/tools/mtmd -I$LLAMA_DIR/examples -I$LLAMA_DIR/ggml/include \
    -L$BUILD_DIR/bin \
    -Wl,--no-as-needed -lmtmd -lllama -lllama-common -lggml -lggml-base -lggml-cpu -lggml-cuda \
    joycaption_wrapper.cpp \
    -o libjoycaption.so \
    -lpthread -ldl

echo "Build OK: libjoycaption.so"
