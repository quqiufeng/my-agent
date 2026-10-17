# camhost — 把本机摄像头/麦克风暴露成局域网 HTTP 流

只用 Python 标准库 + `ffmpeg`/`arecord`，无 pip 依赖；给 my-agent 或任何播放器拉流。

## 接口

| 路径 | 说明 |
|---|---|
| `/info` | JSON：设备、分辨率、麦克风、在线客户端数 |
| `/video` | MJPEG（multipart/x-mixed-replace），`<img src>` 或 OpenCV/ffmpeg 可直接读 |
| `/audio` | WAV 持续流：16 kHz / 单声道 / S16_LE（PCM） |
| `/snap` | 当前帧 JPEG（单张） |

## 环境变量

```
CAM_DEV=/dev/video0   CAM_SIZE=1280x720   CAM_FPS=15   CAM_QUALITY=5
MIC_DEV=plughw:2,0    MIC_RATE=16000      PORT=8080
IDLE_STOP=10          # 无客户端后停采集的秒数（0=不停）
```

## 运行

```bash
python3 camhost.py                      # 前台
PORT=8080 python3 camhost.py
curl http://IP:8080/info
curl -s http://IP:8080/snap -o snap.jpg
```

systemd（以 quqiufeng 身份、附加 audio/video 组）：

```ini
[Service]
ExecStart=/usr/bin/python3 /opt/camhost/camhost.py
Environment=CAM_DEV=/dev/video0
Environment=MIC_DEV=plughw:2,0
User=quqiufeng
SupplementaryGroups=audio video
Restart=always
```

## 接入 my-agent

```bash
# 视频（Flutter 桌面布局里的第 2 路）
export CAM2_URL=http://192.168.1.68:8080/video
# 音频（语音唤醒/识别）
export VOICE_MIC_URL=http://192.168.1.68:8080/audio
# 本机声卡 + 网络麦克风混音（可选）
export VOICE_MIC_MIX=1
```

## 注意

- 摄像头只支持 YUYV 时由 ffmpeg 实时转 MJPEG（720p@15 在 i5-2400 上约 10–20% CPU）。
- 采集是懒启动：有客户端才拉起 ffmpeg/arecord，断开 `IDLE_STOP` 秒后停止。
- `/audio` 是持续流，WAV 头里的长度是占位值，播放器/ffmpeg 按流处理即可。
