// camera_texture.cc — 摄像头 → Flutter GL 纹理（流畅：零 JPEG 解码，直接上屏）
// OpenCV(FFmpeg/V4L2) 采集线程 → 共享帧 → FlTextureGL::populate 上传 GL 纹理。
//
// 支持双路源（各自一个纹理）：
//   路 1「agent/camera」   ：USB(/dev/videoN) 或 RTSP_URL（沿用旧行为）
//   路 2「agent/camera2」  ：URL 流（HLS/RTMP/FLV/RTSP），URL 可来自
//                            env CAM2_URL，或文件（默认 /tmp/myagent_ezviz.url）；
//                            文件模式下每次重连都重读 → 配合刷新脚本可自动跟随过期。
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
#include <cstdio>
#include <cstring>
#include <fstream>
#include <mutex>
#include <sstream>
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

  // 源配置
  bool use_url = false;       // true=URL 流，false=USB 索引
  int idx = 0;                // USB 索引
  std::string url;            // 固定 URL（当 url_file 为空时用）
  std::string url_file;       // 从文件读取 URL（每次重连重读，支持刷新）
  std::string rotate_file;    // 从文件读取旋转角(0/90/180/270)，每次重连重读
  int rotate = 0;             // 当前旋转角
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
static CameraTexture* g_keep_usb = nullptr;
static std::vector<CameraTexture*> g_keep_streams;
static std::vector<std::string> g_stream_labels;

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

static std::string read_first_line(const std::string& path) {
  std::ifstream f(path);
  if (!f.is_open()) return "";
  std::string line;
  std::getline(f, line);
  // 去掉首尾空白
  size_t a = line.find_first_not_of(" \t\r\n");
  if (a == std::string::npos) return "";
  size_t b = line.find_last_not_of(" \t\r\n");
  return line.substr(a, b - a + 1);
}

static std::string read_env_value(const std::string& key) {
  if (const char* e = getenv(key.c_str())) return e;
  const char* home = getenv("HOME");
  if (!home) return "";
  std::ifstream f(std::string(home) + "/.env");
  if (!f.is_open()) return "";
  std::string line;
  while (std::getline(f, line)) {
    if (line.rfind(key + "=", 0) != 0) continue;
    std::string v = line.substr(key.size() + 1);
    size_t a = v.find_first_not_of(" \t\r\n");
    size_t b = v.find_last_not_of(" \t\r\n");
    if (a == std::string::npos) return "";
    v = v.substr(a, b - a + 1);
    if (v.size() >= 2 && (v.front() == '\'' || v.front() == '"') && v.back() == v.front())
      v = v.substr(1, v.size() - 2);
    return v;
  }
  return "";
}

static bool write_snapshot(CamState* st) {
  std::lock_guard<std::mutex> lk(st->m);
  if (st->buf.empty() || st->bw <= 0 || st->bh <= 0) return false;
  try {
    cv::Mat rgba(st->bh, st->bw, CV_8UC4, st->buf.data());
    cv::Mat bgr;
    cv::cvtColor(rgba, bgr, cv::COLOR_RGBA2BGR);
    return cv::imwrite(st->snap_path, bgr);
  } catch (const cv::Exception& e) {
    fprintf(stderr, "[camera] snapshot '%s' failed: %s\n", st->snap_path.c_str(), e.what());
    return false;
  }
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call, gpointer user_data) {
  const gchar* name = fl_method_call_get_name(call);
  if (g_strcmp0(name, "textureId") == 0) {
    CameraTexture* t = g_keep_usb;
    respond_ok(call, fl_value_new_int(t && t->st ? t->st->id : 0));
  } else if (g_strcmp0(name, "streamTextureId") == 0) {
    CameraTexture* t = g_keep_streams.empty() ? nullptr : g_keep_streams[0];
    respond_ok(call, fl_value_new_int(t && t->st ? t->st->id : 0));
  } else if (g_strcmp0(name, "streamIds") == 0) {
    FlValue* list = fl_value_new_list();
    for (CameraTexture* t : g_keep_streams)
      fl_value_append_take(list, fl_value_new_int(t && t->st ? t->st->id : 0));
    respond_ok(call, list);
  } else if (g_strcmp0(name, "labels") == 0) {
    FlValue* list = fl_value_new_list();
    const char* cam1 = getenv("CAM1_LABEL");
    fl_value_append_take(list, fl_value_new_string(cam1 && *cam1 ? cam1 : "USB"));
    for (const auto& label : g_stream_labels)
      fl_value_append_take(list, fl_value_new_string(label.c_str()));
    respond_ok(call, list);
  } else if (g_strcmp0(name, "textureSizes") == 0) {
    FlValue* list = fl_value_new_list();
    auto add_size = [&](CameraTexture* t) {
      int w = 0, h = 0;
      if (t && t->st) {
        std::lock_guard<std::mutex> lk(t->st->m);
        w = t->st->bw;
        h = t->st->bh;
      }
      fl_value_append_take(list, fl_value_new_int(w));
      fl_value_append_take(list, fl_value_new_int(h));
    };
    add_size(g_keep_usb);
    for (CameraTexture* t : g_keep_streams) add_size(t);
    respond_ok(call, list);
  } else if (g_strcmp0(name, "snapshot") == 0) {
    CameraTexture* t = g_keep_usb;
    respond_ok(call, fl_value_new_bool(t && t->st ? write_snapshot(t->st) : false));
  } else if (g_strcmp0(name, "snapshot2") == 0) {
    CameraTexture* t = g_keep_streams.empty() ? nullptr : g_keep_streams[0];
    respond_ok(call, fl_value_new_bool(t && t->st ? write_snapshot(t->st) : false));
  } else {
    g_autoptr(FlMethodResponse) r =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(call, r, nullptr);
  }
}

static void capture_loop(CameraTexture* self) {
  CamState* st = self->st;
  int cw = 1280, ch = 720;
  if (const char* e = getenv("CAM_W")) cw = atoi(e);
  if (const char* e = getenv("CAM_H")) ch = atoi(e);
  while (st->run) {
    // 每次重连都重新解析源（URL 文件模式下可跟随刷新脚本更新）
    std::string url = st->url;
    if (!st->url_file.empty()) {
      std::string r = read_first_line(st->url_file);
      if (!r.empty()) url = r;
    }
    bool use_url = st->use_url || (!st->url_file.empty() && !url.empty());
    // 每次重连重读旋转角（支持运行时改文件）
    if (!st->rotate_file.empty()) {
      std::string r = read_first_line(st->rotate_file);
      if (!r.empty()) st->rotate = atoi(r.c_str());
    }
    cv::VideoCapture cap;
    if (use_url) {
      if (url.empty()) {  // 还没拿到地址，等待刷新
        for (int i = 0; i < 20 && st->run; ++i) usleep(100000);
        continue;
      }
      // 读/打开都设超时：HLS 断流时不会卡死在 read 里（否则纹理冻住）
      const std::vector<int> to = {cv::CAP_PROP_OPEN_TIMEOUT_MSEC, 8000,
                                   cv::CAP_PROP_READ_TIMEOUT_MSEC, 8000};
      cap.open(url, cv::CAP_FFMPEG, to);
    } else {
      int idx = st->idx;
      if (const char* e = getenv("CAM_USB_INDEX")) if (st->idx == 0) idx = atoi(e);
      cap.open(idx, cv::CAP_V4L2);
    }
    if (!cap.isOpened()) {
      for (int i = 0; i < 20 && st->run; ++i) usleep(100000);
      continue;
    }
    if (!use_url) {
      cap.set(cv::CAP_PROP_FOURCC, cv::VideoWriter::fourcc('M', 'J', 'P', 'G'));
      cap.set(cv::CAP_PROP_FRAME_WIDTH, cw);
      cap.set(cv::CAP_PROP_FRAME_HEIGHT, ch);
      cap.set(cv::CAP_PROP_FPS, 30);
    }
    cap.set(cv::CAP_PROP_BUFFERSIZE, 1);
    cv::Mat f;
    while (st->run && cap.read(f)) {
      if (!f.empty()) {
        try {
          if (st->rotate == 90) cv::rotate(f, f, cv::ROTATE_90_CLOCKWISE);
          else if (st->rotate == 180) cv::rotate(f, f, cv::ROTATE_180);
          else if (st->rotate == 270) cv::rotate(f, f, cv::ROTATE_90_COUNTERCLOCKWISE);
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
    if (st->run) {
      fprintf(stderr, "[camera] stream disconnected (%s), reconnecting\n", url.c_str());
      usleep(300000);
    }
  }
}

// 创建并注册一个摄像头纹理源，返回对象（已 keepalive）
static CameraTexture* make_cam(FlTextureRegistrar* tr, bool use_url, int idx,
                               const std::string& url, const std::string& url_file,
                               const std::string& snap_path,
                               const std::string& rotate_file) {
  CameraTexture* self = (CameraTexture*)g_object_new(camera_texture_get_type(), nullptr);
  CamState* st = self->st;
  st->registrar = tr;
  st->use_url = use_url;
  st->idx = idx;
  st->url = url;
  st->url_file = url_file;
  st->snap_path = snap_path;
  st->rotate_file = rotate_file;
  // 占位帧：保证 populate 在拿到真实画面之前也能成功返回。
  st->bw = 2;
  st->bh = 2;
  st->buf.assign(static_cast<size_t>(st->bw) * st->bh * 4, 0);
  fl_texture_registrar_register_texture(tr, FL_TEXTURE(self));
  st->id = fl_texture_get_id(FL_TEXTURE(self));
  st->run = true;
  st->th = std::thread(capture_loop, self);
  st->th.detach();
  // 常驻强引用
  g_object_ref_sink(G_OBJECT(self));
  g_object_ref(G_OBJECT(self));
  return self;
}

void camera_texture_register(FlPluginRegistry* registry) {
  FlPluginRegistrar* pr =
      fl_plugin_registry_get_registrar_for_plugin(registry, "camera_texture");
  FlTextureRegistrar* tr = fl_plugin_registrar_get_texture_registrar(pr);

  // 路 1：USB 或 RTSP_URL（沿用旧行为）
  std::string rtsp = getenv("RTSP_URL") ? getenv("RTSP_URL") : "";
  int idx = 0;
  if (const char* e = getenv("CAM_USB_INDEX")) idx = atoi(e);
  if (!rtsp.empty()) {
    g_keep_usb = make_cam(tr, true, 0, rtsp, "", "/tmp/myagent_cam_rtsp.jpg",
                          "/tmp/myagent_rtsp.rot");
  } else {
    g_keep_usb = make_cam(tr, false, idx, "", "", "/tmp/myagent_cam_usb.jpg",
                          "/tmp/myagent_usb.rot");
  }

  // 路 2+：URL 流（萤石/HLS/RTMP/FLV/RTSP）——URL 来自 env 或文件；启用则各建一个纹理
  struct Spec {
    std::string url, file, snap, rot, label;
  };
  std::vector<Spec> specs;
  auto add_spec = [&](const char* url_env, const char* file_env,
                      const char* def_file, const char* def_snap,
                      const char* def_rot, const char* label_env, const char* label_def) {
    std::string url = getenv(url_env) ? getenv(url_env) : "";
    std::string file = getenv(file_env) ? getenv(file_env) : def_file;
    bool want = false;
    if (!url.empty())
      want = true;
    else {
      std::ifstream probe(file);
      if (probe.good()) want = true;  // 文件存在即启用（此刻可能还没写地址，等刷新脚本写）
    }
    const char* le = getenv(label_env);
    std::string label = (le && *le) ? le : label_def;
    if (want) specs.push_back({url, url.empty() ? file : std::string(""), def_snap, def_rot, label});
  };
  // 全屋四路：USB + 萤石客厅 + 萤石门口 + TP-Link
  // 路2/路3/路4 仍可用 CAM*_URL / CAM*_URL_FILE 覆盖，方便以后换源。
  add_spec("CAM2_URL", "CAM2_URL_FILE", "/tmp/myagent_ezviz.url",
           "/tmp/myagent_cam_stream.jpg", "/tmp/myagent_ezviz.rot", "CAM2_LABEL", "EZVIZ 客厅");
  add_spec("CAM3_URL", "CAM3_URL_FILE", "/tmp/myagent_door.url",
           "/tmp/myagent_cam_door.jpg", "/tmp/myagent_door.rot", "CAM3_LABEL", "EZVIZ 门口");

  std::string tp = read_env_value("CAM4_URL");
  if (tp.empty()) tp = read_env_value("TPLINK_RTSP");
  if (tp.empty()) {
    std::string user = read_env_value("TPLINK_USER");
    std::string pass = read_env_value("TPLINK_PASS");
    std::string host = read_env_value("CAM4_HOST");
    if (host.empty()) host = read_env_value("TPLINK_HOST");
    if (host.empty()) host = "192.168.1.111";
    std::string port = read_env_value("CAM4_PORT");
    if (port.empty()) port = "554";
    std::string path = read_env_value("CAM4_PATH");
    if (path.empty()) path = "/stream1";
    if (!user.empty() && !pass.empty())
      tp = "rtsp://" + user + ":" + pass + "@" + host + ":" + port + path;
  }
  if (!tp.empty()) {
    const char* le = getenv("CAM4_LABEL");
    specs.push_back({tp, "", "/tmp/myagent_cam_rtsp.jpg", "/tmp/myagent_tplink.rot",
                     (le && *le) ? le : "TP-Link"});
  }

  for (const Spec& s : specs) {
    g_keep_streams.push_back(make_cam(tr, true, 0, s.url, s.file, s.snap, s.rot));
    g_stream_labels.push_back(s.label);
  }

  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(pr);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel =
      fl_method_channel_new(messenger, "agent/camera", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr, nullptr);
}
