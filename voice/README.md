# voice — 语音入口（纯 C/C++，无 Python）

my-agent 的第二个入口：**麦克风说话 → 本地识别成文字 → 转发给 Master agent**；以及**文本转语音 → USB 音响播放**。
全链路只用 C/C++ 与 Shell：识别用 `SenseVoice.cpp`，合成用 `sherpa-onnx + Kokoro`。

```
麦克风 ──ALSA──▶ VAD 断句 ──▶ SenseVoice.cpp 识别 ──▶ [语音输入] text ──▶ Master(4097)
文本 ──▶ sherpa-onnx + Kokoro ──▶ WAV ──▶ PipeWire/aplay ──▶ USB 音响
```

## 目录

```
voice/
├── config.sh          # 全部路径/设备/参数（可用环境变量覆盖）
├── say.sh             # 文本 → 语音 → USB 音响（Kokoro，失败回退 espeak-ng）
├── listen.sh          # 启动语音入口（麦克风常驻监听）
├── listen/
│   ├── listen.cpp     # 采集 + VAD 断句 + 调用 SenseVoice + 转发 Master
│   └── Makefile
├── camera.sh          # 摄像头窗口启动
├── camera/
│   ├── camera.cpp     # SDL2 双摄分屏（USB + RTSP）
│   └── Makefile
├── app.sh             # 统一界面启动
├── app/
│   ├── app.cpp        # 画面 + 人脸门控 + 语音监听 + 状态栏（单进程）
│   └── Makefile
├── voice.sh           # 统一入口：say | listen | once | test | camera | app
└── README.md
```

## 依赖（系统）

| 组件 | 用途 | 位置 |
|------|------|------|
| SenseVoice.cpp | 语音转文本（C++ CLI + gguf） | `/opt/SenseVoice.cpp` |
| sherpa-onnx | 文本转语音运行时（C++） | `/opt/sherpa-onnx` |
| Kokoro 多语言模型 | 中文/英文音色 | `/data/models/kokoro-multi-lang-v1_0` |
| libasound2-dev | 编译 `listen` | 系统包 |
| SDL2 + OpenCV | 编译 `camera`（摄像头窗口） | 系统包 |
| espeak-ng | TTS 兜底 | 系统包 |
| PipeWire (`pw-play`) | 播放到 USB 音响 | 系统 |

## 快速使用

```bash
cd /opt/my-agent/voice

# 1. 文本转语音（USB 音响出声）
./voice.sh say "你好，我是星期五"

# 2. 自检一句
./voice.sh test

# 3. 语音入口：常驻监听，识别后转发 Master(4097)
./voice.sh listen

# 4. 只识别一句、不转发（验证麦克风）
./voice.sh once

# 5. 摄像头窗口（USB + RTSP 分屏，双击全屏，ESC 退出）
./voice.sh camera

# 6. 统一界面：画面(人脸门控) + 语音监听 + 状态栏，单进程
./voice.sh app
```

## 统一界面（单进程）

`voice.sh app` 把摄像头画面和语音监听合到一个窗口：

- **上方画面**：USB + RTSP 分屏，人脸门控开启时无人脸自动黑屏
- **下方状态栏**：状态圆点（绿=等待/黄=录音）、麦克风电平条、转发状态、最近识别文本（OpenCV freetype 渲染中文）
- 语音识别到后自动以 `[语音输入]` 转发到 Master（`--no-forward` 可关）
- 无人脸时黑屏，但**音频监听持续运行**

```bash
./voice.sh app                          # 全功能
./voice.sh app --no-audio               # 只要画面
./voice.sh app --no-face-gate           # 一直显示画面
./voice.sh app --no-forward             # 识别但不转发
```

## 摄像头窗口

迁自早期项目的 SDL2 双摄界面，已剥离音频/ASR，仅显示画面（并修复了原代码的纹理泄漏、固定分辨率、RTSP 无重连、硬编码凭据等问题）。

```bash
./voice.sh camera                          # USB + RTSP 分屏
./voice.sh camera --usb-only               # 只显示 USB 摄像头
RTSP_URL=rtsp://user:pass@ip:554/... ./voice.sh camera   # 指定 RTSP
./voice.sh camera --usb 1 --size 1600x900  # 换设备/窗口尺寸
```

| 环境变量 / 参数 | 默认 | 说明 |
|-----------------|------|------|
| `CAM_USB_INDEX` / `--usb N` | `0` | USB 摄像头索引（`/dev/videoN`） |
| `RTSP_URL` / `--rtsp URL` | 空 | RTSP 地址；**不留默认凭据**，留空则只显示 USB |
| `CAM_W` / `CAM_H` / `--size WxH` | `1280x720` | 窗口尺寸（可缩放） |
| `CAM_FACE_GATE` / `--face-gate` `--no-face-gate` | 开 | **人脸门控**：检测不到人脸则不出画面，仅监控音频 |
| `CAM_FACE_TIMEOUT_MS` / `--face-timeout MS` | `1500` | 超过该时长无人脸即隐藏画面 |
| `CAM_FACE_CASCADE` | OpenCV Haar 默认路径 | 人脸分类器 |

人脸门控：用 OpenCV Haar 每 200ms 采样两路画面检测人脸；连续 `timeout` 内无人脸则该路画面隐藏为黑屏，并显示「未检测到人脸 · 仅音频监控中」。人脸重新出现即恢复画面。关掉门控用 `--no-face-gate`。

操作：**双击** 分屏 ↔ 单摄全屏；**ESC** 退出全屏或退出程序；`q` 退出。

## 设备与配置

全部在 `config.sh`，可临时用环境变量覆盖：

| 变量 | 默认 | 说明 |
|------|------|------|
| `VOICE_MIC_DEV` | `plughw:2,0` | 采集设备（USB 摄像头麦克风） |
| `VOICE_MIC_CARD` | `2` | `amixer` 增益对应的声卡号 |
| `VOICE_MIC_GAIN` | `7810` | 采集音量（最大 7810；低了识别不到） |
| `KOKORO_SID` | `47` | 音色 ID（47=`zf_xiaoxiao`，46=`zf_xiaoni`，49=`zm_yunjian`…） |
| `VOICE_SINK` | 空 | PipeWire sink；空=默认（本机默认即 USB 音响 DTC 480） |
| `VOICE_SPEAKER` | `plughw:3,0` | ALSA 兜底播放设备 |
| `AGENT_URL` | `http://localhost:4097` | 转发目标（opencode Master） |

不改代码即可换音色/设备：

```bash
KOKORO_SID=46 ./voice.sh say "换成女声"
VOICE_MIC_DEV=plughw:1,0 ./voice.sh listen
```

## 回复规则（让 AI 用语音回）

语音入口把消息以 `[语音输入] ...` 前缀发给 Master。在 Master 的 `AGENTS.md` 里约定：
收到 `[语音输入]` 的任务，完成后用 `bash /opt/my-agent/voice/say.sh "回复内容"` 回复。

## 故障排查

- **识别不到**：先确认麦克风电平。`arecord -D plughw:2,0 -f S16_LE -r 16000 -c 1 -d 3 /tmp/t.wav`
  再用 `ffmpeg -i /tmp/t.wav -af volumedetect -f null -` 看 `max_volume`；若低于 -20dB，
  `amixer -c 2 sset Mic 7810`（`listen` 启动时会自动设置）。
- **音响没声**：`wpctl status` 看默认 sink 是否为 `DTC 480`；`pw-play 任意.wav` 测试。
- **设备忙**：PipeWire 占用声卡时纯 ALSA `aplay -D plughw` 会报 busy，故默认走 `pw-play`。
- **中英混读数字/日期**：`say.sh` 已启用 Kokoro 的 `number-zh/date-zh` 规则。

## 已知限制

1. SenseVoice 输出可能带 `<|zh|><|NEUTRAL|>` 等特殊标签，`listen` 已自动剥离。
2. 单声道 16kHz；VAD 断句默认 1.2s 静音，可调 `VOICE_SILENCE_MS`。
3. CPU 合成 RTF≈0.45（一句约 1~3s）；需要更快可后续接 sherpa-onnx GPU 版。
