#ifndef CAMERA_TEXTURE_H_
#define CAMERA_TEXTURE_H_

#include <flutter_linux/flutter_linux.h>

// 注册摄像头纹理到 Flutter（OpenCV 采集 → GL 纹理）。
// MethodChannel "agent/camera"：textureId -> 纹理 id；snapshot -> 写一帧到 /tmp 供 agent 读。
void camera_texture_register(FlPluginRegistry* registry);

#endif  // CAMERA_TEXTURE_H_
