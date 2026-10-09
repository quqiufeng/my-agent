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

---

## 实跑记录（4090D 出图镜像 · 目标：只生成抖音短视频）

**镜像自带**：Ubuntu 24.04、`/root/.opencode/bin/opencode`、gcc/g++/git/make/cmake/wget、luajit/tmux/ffmpeg、
Noto CJK、CUDA 12.8（`/usr/local/cuda-12.8`，已进 ldconfig）、python、onnxruntime(py)、
**出图**（`/opt/{sd,comfycli,musubi-tuner}`、`/data/models/image`）。

**另需补（实测）**：
1. `node` 22 + npm（chrome-devtools MCP 用）
2. `google-chrome`（headless）
3. **`apt install libicu74`** —— 克隆库要 `libicu{data,uc,i18n}.so.74`，镜像只有 `.70`
4. 克隆栈：`/opt/cosyvoice.cpp/build/{bin,lib,_deps/onnxruntime/lib}`、`CosyVoice3-2512_F16.gguf`、
   `Fun-CosyVoice3-0.5B/{speech_tokenizer_v3.onnx,campplus.onnx}`、`~/.myagent_voices`
5. **SenseVoice**（`/opt/SenseVoice.cpp` + `/data/models/sense-voice-small-q4_k.gguf`）——
   **Web 面板必装**：用它把上传的克隆音频转写成 prompt 文本，否则 `cosyvoice.sh add` 报“转写失败”。
6. 代码 + `~/douyin/base`（资料包 + 样本）

**仅“命令行出片”可省**：Kokoro/sherpa、`/data/venv/onnxruntime`、wechat-ocr、joycaption、
微信/相机/adb/浏览器工具。（**SenseVoice 在“上传音频自动克隆”的 Web 流程里必需**）

**坑**：
- 素材若打包自 `/home/<user>/...`，而目标机以 root 运行（`HOME=/root`）→ **音色/资料要放到 `/root` 下**，
  否则 `$HOME/.myagent_voices` 找不到。
- 克隆库依赖 ICU **74**（不是 70）。
- CUDA 用镜像自带的 `/usr/local/cuda-12.8`（ldconfig 已收录，无需额外设 `LD_LIBRARY_PATH`）。

**验证结果**：`voice/cosyvoice.sh synth 话术 …` ≈7.4s/句；`video_dub.sh --fg` 出 **49.9s 成片 / 18.6s**，
字幕已烧录（libass 在）。SSH 端口非 22（用 `xgc_ctl.py ssh <id>` 给出的 `-p`）。

---

## Web 面板（上传素材 → 生成短视频）

代码 `web/`（`server.py` **纯标准库**、`index.html`）：表单上传「视频素材 / 克隆音频 / 参考文案」→
后台克隆音色 → `operator/tools/video_dub.sh` 出片 → 前端**倒计时轮询** → 下载。

**启动（在实例上）**：
```bash
cd /opt/my-agent
PORT=80 setsid bash -c "PORT=80 python3 web/server.py" >/tmp/web.log 2>&1 </dev/null &
```

**访问**：
- 实例内：`http://localhost:80/`
- **公网**：`https://<容器ID>-<端口号>.container.x-gpu.com`（跑在 80 端口 → 用 `-80`）
  - 本实例：**https://zkutektl3enbg1fd-80.container.x-gpu.com**
  - 容器 ID = `python3 xgc_ctl.py list` 里的 `id` 字段

**依赖**：CosyVoice 克隆栈 + **SenseVoice**（转写上传音频为 prompt 文本）+ ffmpeg + Noto CJK 字体
（即上述“另需补”的 3~5 项）。上传目录 `web/uploads/`、成片 `web/outputs/`（已 gitignore）。

### 开机自启（该容器**不是 systemd**）

实例 PID1 = `/sbin/docker-init -- /scripts/start.sh`，**无 systemd、无 cron**。但入口脚本 `/scripts/start.sh`
会在每次启动时**执行 `/scripts/start.d/*`** —— 把启动脚本丢进该目录即可自启：

```bash
cat > /scripts/start.d/myagent-web.sh <<'EOF'
#!/bin/bash
cd /opt/my-agent
export HOST=0.0.0.0 PORT=80
exec /usr/bin/python3 /opt/my-agent/web/server.py >>/var/log/myagent-web.log 2>&1
EOF
chmod +x /scripts/start.d/myagent-web.sh
```

手动重启（不重启容器时）：
```bash
setsid /scripts/start.d/myagent-web.sh </dev/null >/dev/null 2>&1 &
```
> 坑：别用 `pkill -f "web/server.py"` —— ssh 命令行自身含该串，会**误杀当前命令**。用 `pgrep -af server.py` 查 PID 再 kill。
> 日志：`/var/log/myagent-web.log`。

---

## 仙宫云镜像初始化（远程部署面板）

把「短视频生成面板」做成**可复用镜像**，镜像里必须带上这些（部署后即用，无需再配）：

| 项 | 内容 |
|----|------|
| 代码 | `/opt/my-agent`（`operator/tools/*.sh`、`voice/*`、`web/*`） |
| 系统依赖 | `node`22+npm、`google-chrome`、`apt install libicu74`；`luajit`/`tmux`/`ffmpeg`/Noto CJK/`CUDA(/usr/local/cuda-12.8)` 镜像自带 |
| 语音栈 | CosyVoice：`/opt/cosyvoice.cpp/build/{bin,lib,_deps/onnxruntime/lib}` + `CosyVoice3-…F16.gguf` + `Fun-CosyVoice3-0.5B/{speech_tokenizer_v3,campplus}.onnx`；SenseVoice：`/opt/SenseVoice.cpp` + `sense-voice-small-q4_k.gguf`；音色：`~/.myagent_voices` |
| 开机自启 | `/scripts/start.d/myagent-web.sh`（入口 `/scripts/start.sh` 会执行 `start.d/*`）→ 起 `python3 web/server.py`（`PORT=80`）。**这是接收网页表单的关键** |
| 桌面快捷方式 | `/.xgcos/desktop/shortvideo.app/`：`info.yaml`(`type: browser` + `props.port: 80`) + `web.png` |
| 资料（可选） | `~/douyin/base`；如需大脑再配 `~/.local/share/opencode/auth.json` |

**桌面快捷方式格式（仙宫云OS，共 3 类）**
```yaml
# web端口类（本项目用这个）
name: 短视频生成
title: 抖音短视频生成面板
icon: web.png
type: browser
props:
    port: 80
```
> `type` 取值：`browser`(web端口) / `terminal`(自定义脚本，配 `main.sh`) / `filemanager`(快速进入文件夹，配 `path`)。
> 官方模板：`wget https://public.x-gpu.com/f/xkNwTx/kjfs240401.zip`，解压参照。
> 改完 `info.yaml` 需**刷新仙宫云OS 页面**才生效；做好后**存成镜像**即随镜像分发。

**部署后验证**
- 容器内：`curl http://localhost:80/api/health` → `{"ok":true}`
- 公网：`https://<实例ID>-80.container.x-gpu.com`
- 容器内网：`http://<实例ID>-80.c.x-gpu.com`
- 仙宫云OS 桌面 → 点「短视频生成」→ 在新窗口打开面板

**坑（速查）**
- SSH 端口**非 22**（用 `python3 xgc_ctl.py ssh <id>` 给出的 `-p`）。
- 桌面快捷方式必须用 `type: browser`；`terminal` 类在无 DISPLAY/非真 X 桌面下起不了 Chrome（报 `Missing X server or $DISPLAY`）。
- 存镜像前确认 `/scripts/start.d/myagent-web.sh` 存在且可执行——否则部署后端口 80 没人监听，表单打不开。
