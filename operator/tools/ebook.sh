#!/usr/bin/env bash
# tools/ebook.sh — 操作连接的 Kindle DXG 电纸书（LuaJIT/终端执行）
# 前提：Kindle 用 USB 连着，且 `ssh kindle` 免密可用（配置见 /opt/my-agent/kindleDGX.md）。
# @desc 操作连接的 Kindle 电纸书：读书、翻页、跳页、调字号、看目录；截当前屏；读屏文本；朗读当前页；自测
# @usage tools/ebook.sh say "读异类" | "下一页" | "上一页" | "跳到第20页" | "第3章" | "字号大" | "目录" | "书架"
#        tools/ebook.sh state           # 当前状态(mode/page/npages/size/book)
#        tools/ebook.sh shot [out.png]  # 截当前屏(824x1200)，可再 wechat_send_file.sh 发回
#        tools/ebook.sh dump            # 当前屏可见文本（免 OCR）
#        tools/ebook.sh speak           # 朗读当前页（TTS 到 USB 音响）
#        tools/ebook.sh books           # 可读书列表
#        tools/ebook.sh test            # 冒烟自测（PASS/FAIL）
#        tools/ebook.sh log [n] | restart | status
# @rule **电纸书**：用户说“在电纸书上看/读某本书、翻页、上一页/下一页、跳到第几页、调字号、看目录、把电纸书画面发我、念一下这页” → 用 `tools/ebook.sh`。读书 `ebook.sh say "读<书名>"`；翻页/跳页/字号 `say "<指令>"`；要画面 `ebook.sh shot /tmp/ebook.png` 再 `tools/wechat_send_file.sh`；要朗读 `ebook.sh speak`。不确定状态先 `ebook.sh state`。**不要**自己拼 ssh/scp 命令。
# @order 24
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec luajit "$DIR/ebook.lua" "$@"
