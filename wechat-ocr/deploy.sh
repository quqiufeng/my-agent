#!/bin/bash
# WeChat OCR 部署打包脚本
# 打包所有依赖，拷贝到目标机器即可运行

set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-/tmp/wechat-ocr-deploy}"

echo "=== 打包 WeChat OCR ==="
rm -rf "$OUT"
mkdir -p "$OUT"/{lib,lua,models}

# 1. C 动态库
cp "$DIR/lib/libwechat_ocr_core.so" "$OUT/lib/"

# 2. Lua 脚本
cp "$DIR/lua/"*.lua "$OUT/lua/" 2>/dev/null || true
cp "$DIR/run.lua" "$OUT/"
cp "$DIR/run_ops.lua" "$OUT/" 2>/dev/null || true

# 3. 模型文件
cp "$DIR/models/"*.onnx "$OUT/models/"
cp "$DIR/ppocr_keys_v1.txt" "$OUT/"

# 4. 部署说明
cat > "$OUT/README.txt" << 'EOF'
部署步骤:
1. sudo apt install luajit xdotool xclip ffmpeg vlc
2. 将 onnxruntime-linux-x64-gpu-1.26.0 拷贝到 /data/venv/
   或修改 run.sh 中的 LD_LIBRARY_PATH
3. sudo cp -r lualib/wechat_ocr /usr/local/lualib/
4. 运行: cd wechat-ocr && LD_LIBRARY_PATH=lib:/data/venv/... luajit run.lua

必要环境:
  - LuaJIT 2.1+
  - ONNX Runtime GPU 1.26.0 (libonnxruntime.so)
  - X11 桌面环境
  - NVIDIA GPU + CUDA 12.x (GPU 加速)
EOF

# 5. 打包
cd /tmp
tar czf wechat-ocr-deploy.tar.gz wechat-ocr-deploy/
echo ""
echo "=== 打包完成 ==="
echo "目录: $OUT"
echo "压缩包: /tmp/wechat-ocr-deploy.tar.gz"
ls -lh /tmp/wechat-ocr-deploy.tar.gz
