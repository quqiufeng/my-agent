# my-agent 桌面界面（Flutter / Yaru / Kami）

把原 SDL2/OpenCV 常驻界面（摄像头 + 语音状态栏）用 Flutter 重写，复用 WordCard 的桌面方案。

- 框架：Flutter Desktop + Yaru（`yaru ^10.2.0`，锁 `platform 3.1.6`）
- 设计：Kami（暖米纸底 / 单一油墨蓝 / 衬线）见 `lib/theme/app_theme.dart`
- 视频：`media_kit`（libmpv）——USB(`av://v4l2:/dev/videoN`) + RTSP 分屏，双击全屏
- 语音/人脸：后续经 `dart:ffi` 调 C ABI 库（与 agentkit/LuaJIT 共用）
- 字体：Maple Mono NF CN（界面）+ 仓耳今楷 02（衬线）

## 构建 / 运行
```bash
gui/flutter/build.sh        # pub get + flutter build linux --release
gui/flutter/run.sh          # 运行（未构建自动构建）
gui/flutter/launch.sh       # 桌面图标入口（会话内、单实例）
```
产物：`gui/flutter/build/linux/x64/release/bundle/myagent_ui`

环境变量：`CAM_USB_INDEX`(默认0) `RTSP_URL` `CAM_USB_ONLY=1`。

## 依赖
系统需 `libmpv-dev`（media_kit_video 编译用）。
