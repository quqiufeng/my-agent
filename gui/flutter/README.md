# my-agent 桌面界面（Flutter / Yaru / Kami）

入口界面：**全屋四路摄像头 + 语音状态栏**。

- 框架：Flutter Desktop + Yaru（`yaru ^10.2.0`）
- 设计：Kami 暖米纸底 / 油墨蓝 / 衬线
- 视频：原生 `camera_texture.cc`（OpenCV 采集 → FlTextureGL），2×2 网格，双击单路全屏
- 默认四路：
  1. USB `/dev/video0`
  2. EZVIZ 客厅 `/tmp/myagent_ezviz.url`（横屏，不旋转）
  3. EZVIZ 门口 `/tmp/myagent_door.url`
  4. TP-Link RTSP（`~/.env` 的 `TPLINK_RTSP` / `TPLINK_USER` / `TPLINK_PASS`）
- 每格左上角显示摄像头名称；断流会自动重连
- 语音/人脸：后续经 `dart:ffi` 调 C ABI 库
- 字体：Maple Mono NF CN + 仓耳今楷

## 构建 / 运行

```bash
gui/flutter/build.sh        # pub get + flutter build linux --release
gui/flutter/run.sh          # 运行（未构建自动构建）
gui/flutter/launch.sh       # 桌面图标入口（会话内、单实例）
```

产物：`gui/flutter/build/linux/x64/release/bundle/myagent_ui`

## 视频源覆盖

- `CAM2_URL` / `CAM2_URL_FILE`：覆盖客厅萤石
- `CAM3_URL` / `CAM3_URL_FILE`：覆盖门口萤石
- `CAM4_URL`：覆盖 TP-Link
- 旋转：`/tmp/myagent_ezviz.rot`、`/tmp/myagent_door.rot`、`/tmp/myagent_tplink.rot`

默认客厅萤石不旋转；需要旋转时改文件后重连生效。
