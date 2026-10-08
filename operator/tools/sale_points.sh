#!/usr/bin/env bash
# tools/sale_points.sh — 读取「带货引流视频」资料包（说明 + 卖点），供大脑写文案前读取
# @desc 读取带货引流视频资料包（规则说明 + 卖点）
# @usage tools/sale_points.sh
# @rule **做带货引流视频文案前，先跑 `tools/sale_points.sh`** 读取资料包（规则+卖点），再严格按其中规则写文案，然后用 `tools/video_dub.sh` 出片。
# @order 13
DIR="${DOUYIN_DIR:-$HOME/douyin/base}"
[ -f "$DIR/README.md" ] && cat "$DIR/README.md"
echo
echo "================ 卖点 (sale_points.txt) ================"
[ -f "$DIR/sale_points.txt" ] && cat "$DIR/sale_points.txt"
echo
echo "================ 参考口播文案（账号真实稿，模仿其语气/结构；ASR 初稿，勿照抄错别字与品牌名）================"
[ -f "$DIR/文案_音频.txt" ] && sed -E 's/^[0-9]+_[0-9]+\.mp4[[:space:]]*//' "$DIR/文案_音频.txt"
