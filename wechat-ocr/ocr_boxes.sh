#!/usr/bin/env bash
# wechat-ocr/ocr_boxes.sh <图片>  — 输出 PP-OCR 文本框：每行 "x<TAB>y<TAB>w<TAB>h<TAB>text"
set -uo pipefail
export IMG="${1:?用法: ocr_boxes.sh <图片>}"
exec luajit -e '
package.path="/opt/my-agent/agentkit/?.lua;"..package.path
local ocr=require("ocr")
for _,b in ipairs(ocr.run(os.getenv("IMG"))) do
  io.write(string.format("%d\t%d\t%d\t%d\t%s\n", b.x, b.y, b.w, b.h, b.text))
end
'
