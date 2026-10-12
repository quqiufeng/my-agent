// camera_texture.cc — 摄像头 → Flutter GL 纹理（流畅：零 JPEG 解码，直接上屏）
// OpenCV(V4L2) 采集线程 → 共享帧 → FlTextureGL::populate 上传 GL 纹理。
//
// 注意：本对象的实例由 GObject（g_object_new）分配，**不会执行 C++ 构造函数**，
// 因此不能把 std::string / std::vector / std::mutex / std::thread 等带构造的
// 成员直接放在 GObject 结构体里（会是未初始化内存）。所有 C++ 状态统一放在
// 堆上的 CamState，由 camera_texture_init() 里 new 出来。
#include "camera_texture.h"

#include <epoxy/gl.h>

#include <opencv2/opencv.hpp>

#include <flutter_linux/flutter_linux.h>

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

struct CamState {
  GLuint tex = 0;
  std::thread th;
  std::atomic<bool> run{false};
  std::mutex m;
  std::vector<uint8_t> buf;  // 最新帧（RGBA 裸缓冲，跨线程安全）
  int bw = 0;
  int bh = 0;
  FlTextureRegistrar* registrar = nullptr;
  int64_t id = 0;
  std::string snap_path = "/tmp/myagent_cam_usb.jpg";
};

struct _CameraTexture {
  FlTextureGL parent_instance;
  CamState* st = nullptr;  // 由 camera_texture_init() 初始化
};

typedef struct _CameraTexture CameraTexture;
typedef struct _CameraTextureClass {
  FlTextureGLClass parent_class;
} CameraTextureClass;

// 常驻引用，防止纹理对象被 GC 回收
static CameraTexture* g_cam_keepalive = nullptr;

G_DEFINE_TYPE(CameraTexture, camera_texture, fl_texture_gl_get_type())

static gboolean cam_populate(FlTextureGL* texture, guint32* target, guint32* name,
                             guint32* width, guint32* height, GError** error) {
  CameraTexture* self = (CameraTexture*)texture;
  CamState* st = self->st;
  if (st == nullptr) return FALSE;
  std::lock_guard<std::mutex> lk(st->m);
  if (st->buf.empty() || st->bw <= 0 || st->bh <= 0) return FALSE;
  if (st->tex == 0) glGenTextures(1, &st->tex);
  glBindTexture(GL_TEXTURE_2D, st->tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, st->bw, st->bh, 0, GL_RGBA,
               GL_UNSIGNED_BYTE, st->buf.data());
  *target = GL_TEXTURE_2D;
  *name = st->tex;
  *width = st->bw;
  *height = st->bh;
  return TRUE;
}

static void camera_texture_class_init(CameraTextureClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = cam_populate;
}

static void camera_texture_init(CameraTexture* self) {
  if (self->st == nullptr) self->st = new CamState();
}

static void respond_ok(FlMethodCall* call, FlValue* v) {
  g_autoptr(FlMethodResponse) r = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
  fl_method_call_respond(call, r, nullptr);
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call, gpointer user_data) {
  CameraTexture* self = (CameraTexture*)user_data;
  CamState* st = self->st;
  const gchar* name = fl_method_call_get_name(call);
  if (g_strcmp0(name, "textureId") == 0) {
    respond_ok(call, fl_value_new_int(st->id));
  } else if (g_strcmp0(name, "snapshot") == 0) {
    bool ok = false;
    {
      std::lock_guard<std::mutex> lk(st->m);
      if (!st->buf.empty() && st->bw > 0 && st->bh > 0) {
        try {
          cv::Mat rgba(st->bh, st->bw, CV_8UC4, st->buf.data());
          cv::Mat bgr;
          cv::cvtColor(rgba, bgr, cv::COLOR_RGBA2BGR);
          ok = cv::imwrite(st->snap_path, bgr);
        } catch (const cv::Exception& e) {
          fprintf(stderr, "[camera] snapshot '%s' failed: %s\n",
                  st->snap_path.c_str(), e.what());
          ok = false;
        }
      }
    }
    respond_ok(call, fl_value_new_bool(ok));
  } else {
    g_autoptr(FlMethodResponse) r =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(call, r, nullptr);
  }
}

static void capture_loop(CameraTexture* self) {
  CamState* st = self->st;
  int idx = 0;
  if (const char* e = getenv("CAM_USB_INDEX")) idx = atoi(e);
  int cw = 1280, ch = 720;
  if (const char* e = getenv("CAM_W")) cw = atoi(e);
  if (const char* e = getenv("CAM_H")) ch = atoi(e);
  std::string rtsp = getenv("RTSP_URL") ? getenv("RTSP_URL") : "";
  while (st->run) {
    cv::VideoCapture cap;
    if (!rtsp.empty()) {
      cap.open(rtsp, cv::CAP_FFMPEG);
      st->snap_path = "/tmp/myagent_cam_rtsp.jpg";
    } else {
      cap.open(idx, cv::CAP_V4L2);
    }
    if (!cap.isOpened()) {
      for (int i = 0; i < 20 && st->run; ++i) usleep(100000);
      continue;
    }
    cap.set(cv::CAP_PROP_FOURCC, cv::VideoWriter::fourcc('M', 'J', 'P', 'G'));
    cap.set(cv::CAP_PROP_FRAME_WIDTH, cw);
    cap.set(cv::CAP_PROP_FRAME_HEIGHT, ch);
    cap.set(cv::CAP_PROP_FPS, 30);
    cap.set(cv::CAP_PROP_BUFFERSIZE, 1);
    cv::Mat f;
    while (st->run && cap.read(f)) {
      if (!f.empty()) {
        try {
          cv::Mat rgba;
          cv::cvtColor(f, rgba, cv::COLOR_BGR2RGBA);
          {
            std::lock_guard<std::mutex> lk(st->m);
            size_t n = rgba.total() * rgba.elemSize();
            st->buf.assign(rgba.data, rgba.data + n);
            st->bw = rgba.cols;
            st->bh = rgba.rows;
          }
        } catch (const cv::Exception& e) {
          fprintf(stderr, "[camera] frame convert failed: %s\n", e.what());
          continue;
        }
        if (st->registrar)
          fl_texture_registrar_mark_texture_frame_available(st->registrar,
                                                            FL_TEXTURE(self));
      }
    }
    cap.release();
    if (st->run) usleep(300000);
  }
}

void camera_texture_register(FlPluginRegistry* registry) {
  FlPluginRegistrar* pr =
      fl_plugin_registry_get_registrar_for_plugin(registry, "camera_texture");
  FlTextureRegistrar* tr = fl_plugin_registrar_get_texture_registrar(pr);

  CameraTexture* self = (CameraTexture*)g_object_new(camera_texture_get_type(), nullptr);
  CamState* st = self->st;
  st->registrar = tr;
  // 占位帧：保证 populate 在拿到真实画面之前也能成功返回。
  st->bw = 2;
  st->bh = 2;
  st->buf.assign(static_cast<size_t>(st->bw) * st->bh * 4, 0);
  fl_texture_registrar_register_texture(tr, FL_TEXTURE(self));
  st->id = fl_texture_get_id(FL_TEXTURE(self));

  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(pr);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel =
      fl_method_channel_new(messenger, "agent/camera", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, self, nullptr);

  st->run = true;
  st->th = std::thread(capture_loop, self);
  st->th.detach();

  // 常驻强引用：纹理对象由注册器与采集线程长期使用，绝不能被 GLib 回收。
  g_object_ref_sink(G_OBJECT(self));
  g_object_ref(G_OBJECT(self));
  g_cam_keepalive = self;
  (void)g_cam_keepalive;
}
