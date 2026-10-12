#!/usr/bin/env bash
# wechat-ocr/ocr_text.sh <图片> <输出txt>  — 用 agentkit PP-OCRv4 读出图片文字写入文件
# （C 库的 [OCR] 日志走 stdout，故结果单独写文件，避免污染）
set -uo pipefail
IMG="${1:?用法: ocr_text.sh <图片> <输出txt>}"
OUT="${2:?用法: ocr_text.sh <图片> <输出txt>}"
export IMG OUT
exec luajit -e '
package.path="/opt/my-agent/agentkit/?.lua;"..package.path
local ocr=require("ocr")
local s=ocr.text(os.getenv("IMG"))
local f=io.open(os.getenv("OUT"),"w"); if f then f:write(s); f:close() end
'
