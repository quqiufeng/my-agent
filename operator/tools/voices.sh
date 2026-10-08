#!/usr/bin/env bash
# tools/voices.sh — 克隆音色：管理 + 用指定音色发声（CosyVoice3，纯 C++/LuaJIT FFI）
# @desc 克隆音色：列出/注册/删除音色，或用指定音色发声
# @usage tools/voices.sh list | add <名> <参考.wav> ["参考文本"] | del <名> | say <名> "文本" [语速]
# @rule **克隆音色 / 指定某人音色发声**：说“用 X 的声音说 … / 克隆 X 的音色 / 有哪些音色”→ 先 `tools/voices.sh list` 看已注册的。要**新增**音色需用户提供一段 **3–30 秒参考音频（.wav 路径）**：`tools/voices.sh add <名> <参考.wav> ["参考文本"]`（不给文本会用 SenseVoice 自动转写，稍慢）；然后用 `tools/say.sh --voice <名> "内容"` 发声（或 `tools/voices.sh say <名> "内容"`）。删除：`tools/voices.sh del <名>`。
# @order 7
exec /opt/my-agent/voice/cosyvoice.sh "$@"
