#!/usr/bin/env bash
# tools/now.sh — 返回当前日期与时间
# @rule **问时间/日期**（“现在几点 / 今天几号 / 星期几”）→ 用 `now.sh`，不要为此调浏览器或其它工具。
# @order 5
# 用途：回答“现在几点 / 今天几号 / 星期几”等，避免为此调用浏览器或其它越权命令。
set -uo pipefail
date '+%Y-%m-%d %H:%M:%S %A'
