# CamStream — 把 Android 手机变成监控摄像头/麦克风

无 root，用 Camera2 + AudioRecord + 一个极简 HTTP 服务，把**后置摄像头画面**和**麦克风声音**
通过局域网推给任何程序（ffmpeg / VLC / OpenCV / 浏览器）。

## 接口

| 路径 | 内容 |
|---|---|
| `http://<手机IP>:8080/info` | JSON：可用摄像头 + 当前使用哪一颗 |
| `http://<手机IP>:8080/video` | MJPEG（当前摄像头，1280×720，约 10fps，每帧 ~75KB） |
| `http://<手机IP>:8080/video?cam=back` | 切到后置并推流 |
| `http://<手机IP>:8080/video?cam=front` | 切到前置并推流 |
| `http://<手机IP>:8080/audio` | WAV 流（PCM 16bit / 16kHz / 单声道） |
| `http://<手机IP>:8080/` | 状态页 |

- 前台服务 + `PARTIAL_WAKE_LOCK`：**熄屏也持续推流**（实测屏幕 OFF 仍 7fps）
- 视频走 Camera2（YUV_420_888 → JPEG），音频走 AudioRecord
- 无鉴权，仅限可信局域网

## 构建

依赖：JDK **17**（d8 与 JDK 21 的匿名类不兼容）、Android SDK `build-tools;34.0.0`、`platforms;android-30`。

```bash
./build.sh        # 产物 build/camstream.apk
```

不用 Gradle：`javac → d8 → aapt2 link → zip(classes.dex) → zipalign → apksigner`。

## 安装（vivo 注意）

```bash
adb install -r build/camstream.apk
```

vivo 会要求「vivo 账号密码」验证（即使已解锁）。绕过办法：安装前先
`adb shell am force-stop com.bbk.account`，再在安装弹窗里勾选「已了解风险」→「继续安装」。

装完授权并启动：

```bash
adb shell pm grant com.example.camstream android.permission.CAMERA
adb shell pm grant com.example.camstream android.permission.RECORD_AUDIO
adb shell am start -n com.example.camstream/.MainActivity
```

> 也可以 `am startservice -n com.example.camstream/.StreamService` 无界面启动，
> 但 Android 11 会限制后台启动前台服务（`startForegroundCount=0`），所以推荐起 Activity。

## 主机侧工具

```bash
phone-cam info                     # 摄像头列表/当前
phone-cam view back                # 实时看后置（front 为前置）
phone-cam audio                    # 只听声音
phone-cam snap out.jpg front       # 抓一帧（可指定摄像头）
phone-cam record ~/mon 600 back    # 录 mp4（视频+音频，600s 一段）
phone-monitor ~/mon 600            # = 启动 App + record（后置）
```

对外接口（局域网内任何程序可直接用）：

```bash
curl http://<手机IP>:8080/info
ffplay "http://<手机IP>:8080/video?cam=front"
ffplay "http://<手机IP>:8080/audio"
ffmpeg -i "http://<手机IP>:8080/video?cam=back" -i "http://<手机IP>:8080/audio" out.mp4
```

## 开机自启

Termux 的开机脚本里（`~/.termux/boot/start.sh`）加：

```bash
[ -f ~/monitor.enable ] && am start -n com.example.camstream/.MainActivity
```

`touch ~/monitor.enable` 开启，删除则关闭。

## 限制

- MJPEG 每帧是独立 JPEG，带宽约 6 Mbps@10fps；想要 H.264 需要改用 MediaCodec + 封装
- 音频只支持一个客户端（共享队列）
- 无鉴权/无加密
- 相机在屏幕关闭后仍工作，但部分厂商省电策略可能杀进程，需把 App 加入电池白名单
