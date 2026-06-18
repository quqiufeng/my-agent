#!/bin/bash
# ============================================================
# WeChat OCR - 自动发送消息 + 录屏 完整流程
# ============================================================
# 用法:
#   ./wechat_send_and_record.sh "要发送的消息"
#   ./wechat_send_and_record.sh "你好"              # 默认录15秒
#   ./wechat_send_and_record.sh "你好" 20           # 录20秒
#   ./wechat_send_and_record.sh                      # 使用默认消息
#
# 流程:
#   1. 点底部绿色微信图标 → 打开微信
#   2. 逐字输入消息 → 回车发送
#   3. 自动读取聊天内容验证
#   4. 全程录屏保存到 ~/wechat_record.mp4
#   5. VLC 自动播放录像
# ============================================================

set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
MSG="${1:-你好，这是自动发送的测试消息}"
DURATION="${2:-15}"
OUTPUT="$HOME/wechat_record.mp4"

# 环境变量
export LD_LIBRARY_PATH="$DIR/lib:/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib"
export LUA_PATH="/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;;"
export LUA_CPATH="/usr/local/lualib/?.so;;"

echo "=========================================="
echo " WeChat 自动发送 + 录屏"
echo "=========================================="
echo " 消息: $MSG"
echo " 时长: ${DURATION}秒"
echo " 录像: $OUTPUT"
echo "=========================================="
echo ""

# 检查依赖
command -v ffmpeg >/dev/null 2>&1 || { echo "请安装 ffmpeg"; exit 1; }
command -v xdotool >/dev/null 2>&1 || { echo "请安装 xdotool"; exit 1; }
command -v xclip >/dev/null 2>&1 || { echo "请安装 xclip"; exit 1; }

# ====== 第1步: 开始录屏 ======
echo "[1/5] 开始录屏 (${DURATION}秒)..."
ffmpeg -y -f x11grab -r 10 -s 2560x1440 -i :0.0 \
  -vcodec libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
  -t "$DURATION" "$OUTPUT" &
FFPID=$!
sleep 1

# ====== 第2步: 初始化 OCR ======
echo "[2/5] 加载 OCR 模型..."
LUA_SCRIPT=$(cat << 'LUAEOF'
local ffi = require("ffi")
ffi.cdef[[void usleep(unsigned int);]]
local ocr = require("wechat_ocr")
local dir = ...
ocr.init(dir .. "/models/ch_PP-OCRv4_det_infer.onnx",
         dir .. "/models/ch_PP-OCRv4_rec_infer.onnx",
         dir .. "/ppocr_keys_v1.txt")
-- 点微信图标
print("1. 点微信图标...")
ocr.open(2000)
ffi.C.usleep(800000)
-- 输入并发送
local msg = arg[1] or "你好，自动发送测试消息"
print("2. 输入: " .. msg)
ocr.send(msg)
ffi.C.usleep(2000000)
-- 读取验证
os.execute("xdotool search --name 微信 windowactivate 2>/dev/null")
ffi.C.usleep(500000)
print("3. 聊天内容:")
local text = ocr.capture()
if text then
    for line in text:gmatch("[^\n]+") do
        print("   " .. line)
    end
end
ocr.destroy()
print("4. 完成")
LUAEOF
)

/usr/local/bin/luajit -e "$LUA_SCRIPT" "$DIR" "$MSG" 2>/dev/null

# ====== 第3步: 等待录屏结束 ======
echo "[3/5] 等待录屏结束..."
wait $FFPID 2>/dev/null || true

# ====== 第4步: 播放录像 ======
echo "[4/5] 播放录像..."
ls -lh "$OUTPUT"
vlc "$OUTPUT" 2>/dev/null &

# ====== 第5步: 完成 ======
echo "[5/5] 完成!"
echo ""
echo "  📁 录像: $OUTPUT"
echo "  ▶  播放: vlc $OUTPUT"
echo ""
