# my-agent 部署清单

> 脚本大量使用**绝对路径**（`/opt`、`/data`）。目标机要么保持同路径，要么用**同名环境变量覆盖**
> （`voice/config.sh` 里所有 `SENSEVOICE_*`、`KOKORO_*`、`COSYVOICE_*`、`SHERPA_*` 等均可覆盖）。
>
> **出图相关（`/opt/static_comfyui`、`/data/models/image`、图片描述 VLM）已在基础镜像里，无需搬运。**

配套脚本：`operator/deploy_pack.sh`（`--check` 校验、`--pack` 打包 + 清单 + scp 提示）。

---

## 1. 代码（git clone，不用 scp）

```
operator/        # 大脑：tools/*.sh、*.lua、opencode.json、guard.js、TOOLS.md
voice/           # 语音：*.c/*.cpp/*.h/*.sh/*.lua + 配置
wechat-ocr/      # 微信入口：*.lua + C++ 源码 + bridge.sh
remote.sh start.sh *.md
```

## 2. 编译产物 / 二进制（被 `.gitignore` 排除，需 scp 或目标机重编）

| 资源 | 路径 | 大小 | 备注 |
|------|------|------|------|
| 语音界面 | `voice/listen/listen`、`voice/orb/orb`、`voice/app/app`、`voice/camera/camera` | 小 | 可 `make -C voice/<x>` 重编 |
| 微信 OCR 库 | `wechat-ocr/lib/libwechat_ocr_core.so` | — | 可 cmake 重编 |
| 微信 OCR 模型 | `wechat-ocr/models/ch_PP-OCRv4_{det,rec}_infer.onnx` | 15M | |
| 图片描述库 | `joycaption-wrapper/libjoycaption.so` | 0.1M | |
| opencode 插件依赖 | `operator/.opencode/node_modules`（+ package.json/lock） | 63M | |

## 3. 外部绝对路径模型 / 运行时（必须搬运）

| 用途 | 路径 | 大小 |
|------|------|------|
| ASR 程序 | `/opt/SenseVoice.cpp`（`bin/sense-voice-main`） | 359M |
| ASR 权重 | `/data/models/sense-voice-small-q4_k.gguf` | 174M |
| TTS 程序 | `/opt/sherpa-onnx` | 83M |
| Kokoro 权重 | `/data/models/kokoro-multi-lang-v1_0` | 384M |
| 克隆库/CLI | `/opt/cosyvoice.cpp/build/{bin,lib}` | 156M |
| 克隆模型 | `/data/models/cosyvoice3-gguf/CosyVoice3-2512_F16.gguf` | 1.7G |
| 克隆前端 onnx | `/data/models/Fun-CosyVoice3-0.5B/{speech_tokenizer_v3.onnx,campplus.onnx}` | 952M |
| ONNX Runtime | `/data/venv/onnxruntime-linux-x64-gpu-1.26.0` | 356M |
| 克隆音色库 | `~/.myagent_voices/`（`话术.gguf` 等） | 13M |

> `Fun-CosyVoice3-0.5B/` 整个 9.1G，但**只用到上面 2 个 onnx**，别整目录搬。

**核心合计 ≈ 4.5G。**

## 4. 系统依赖（视镜像是否预装）

`opencode` 1.18.35、`node`/`npx`、`luajit`、`tmux`、`ffmpeg`、`curl`、`adb`、`google-chrome`、
字体 **Noto Sans CJK SC Bold**、微信 PC 客户端 `/opt/wechat/wechat`（需登录）、声卡/麦克风/相机。

- 音频设备在 `voice/config.sh`：`VOICE_MIC_DEV`（默认 `plughw:2,0`）、`VOICE_SPEAKER`（默认 `plughw:3,0`），**按目标机改**。
- Chrome 需带 `--remote-debugging-port` 启动（大脑/工具走 DevTools）。

## 5. 配置 / 凭据

- `~/.env`：`WEBDAV_{URL,USER,PASS,MUSIC,SEARCH}`、`FUYAO_API_KEY`、`WEIBO_COOKIE`
- `operator/opencode.json`、`operator/.opencode/plugin/guard.js`（随仓库）

---

## 部署步骤

```bash
# 0) 基础镜像已含：出图(static_comfyui + /data/models/image)、torch/CUDA、微信
# 1) 取代码
git clone <repo> /opt/my-agent

# 2) 校验目标机现有资源（缺什么补什么）
/opt/my-agent/operator/deploy_pack.sh --check

# 3) 在源机打包核心资源（含绝对路径，解包用 -P）
/opt/my-agent/operator/deploy_pack.sh --pack /tmp/myagent-core.tgz
scp /tmp/myagent-core.tgz <user>@<host>:/tmp/
ssh <user>@<host> 'sudo tar xzf /tmp/myagent-core.tgz -C / -P'   # 还原到相同绝对路径

# 4) 如二进制/库缺失则重编
make -C /opt/my-agent/voice/listen && make -C /opt/my-agent/voice/app
make -C /opt/my-agent/voice/camera  && make -C /opt/my-agent/voice/orb
# 微信 OCR 库：
cd /opt/my-agent/wechat-ocr && cmake -S . -B build_lib -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="/data/venv/onnxruntime-linux-x64-gpu-1.26.0/lib/cmake" \
  && cmake --build build_lib -j"$(nproc)" --target wechat_ocr_core

# 5) 校对 voice/config.sh 的设备号；启动
/opt/my-agent/voice/app/app        # 语音统一界面
/opt/my-agent/operator/start.sh    # 大脑 + tui（+ bridge）
```

## 校验清单（`deploy_pack.sh --check` 会逐项打印）

代码目录、§2 编译产物、§3 模型/运行时、§5 配置、系统命令（luajit/tmux/ffmpeg/opencode/chrome/adb）。

## 待实测（等有卡后）

拿到 GPU 后**照上面实跑一遍**，把缺的依赖/路径差异回填到本文件与 `deploy_pack.sh` 的清单里。
