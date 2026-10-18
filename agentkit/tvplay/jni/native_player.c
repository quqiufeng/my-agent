#define _GNU_SOURCE
// native_player.c — NDK 播放内核：HTTP 拉流(自带预读) → AMediaExtractor 解封装
// → MediaCodec 硬解（视频直接渲到 ANativeWindow，音频走 AAudio）
//
// 由 MainActivity 通过 JNI 调用：init(surface,url) / pause / resume / seek(ms) / stop / position()
#include <jni.h>

#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <media/NdkMediaCodec.h>
#include <media/NdkMediaDataSource.h>
#include <media/NdkMediaExtractor.h>
#include <media/NdkMediaFormat.h>

#include <aaudio/AAudio.h>

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define TAG "tvplay-native"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

#define CACHE_CAP (8 * 1024 * 1024)   // 预读缓存 8MB
#define READ_CHUNK (256 * 1024)

// ---------------- HTTP 数据源 ----------------

typedef struct {
    char host[256];
    char path[1024];
    int port;
    int sock;
    int64_t pos;          // 当前 socket 的读取偏移
    int64_t size;         // 远端总大小（未知=-1）
    unsigned char *cache;
    size_t cacheLen;
    int64_t cacheStart;
    pthread_mutex_t lock;
} HttpSrc;

static int64_t now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

static int http_open(HttpSrc *h, int64_t offset) {
    if (h->sock >= 0) { close(h->sock); h->sock = -1; }
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    char portstr[16];
    snprintf(portstr, sizeof(portstr), "%d", h->port);
    if (getaddrinfo(h->host, portstr, &hints, &res) != 0 || !res) return -1;
    int s = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (s < 0) { freeaddrinfo(res); return -1; }
    struct timeval tv = {10, 0};
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    if (connect(s, res->ai_addr, res->ai_addrlen) != 0) {
        close(s); freeaddrinfo(res); return -1;
    }
    freeaddrinfo(res);
    char req[2048];
    int n = snprintf(req, sizeof(req),
                     "GET %s HTTP/1.1\r\nHost: %s:%d\r\nRange: bytes=%lld-\r\n"
                     "Connection: close\r\nUser-Agent: tvplay\r\n\r\n",
                     h->path, h->host, h->port, (long long)offset);
    if (send(s, req, n, 0) != n) { close(s); return -1; }
    // 读响应头
    char hdr[4096];
    size_t hl = 0;
    while (hl < sizeof(hdr) - 1) {
        if (recv(s, hdr + hl, 1, 0) != 1) { close(s); return -1; }
        if (hl >= 3 && hdr[hl - 3] == '\r' && hdr[hl - 2] == '\n' &&
            hdr[hl - 1] == '\r' && hdr[hl] == '\n') { hl++; break; }
        hl++;
    }
    hdr[hl] = 0;
    if (strncmp(hdr, "HTTP/1.1 200", 12) != 0 && strncmp(hdr, "HTTP/1.1 206", 12) != 0) {
        LOGE("http status: %.20s", hdr);
        close(s);
        return -1;
    }
    char *cr = strcasestr(hdr, "Content-Range:");
    if (cr) {
        char *slash = strchr(cr, '/');
        if (slash) h->size = atoll(slash + 1);
    } else {
        char *cl = strcasestr(hdr, "Content-Length:");
        if (cl) h->size = atoll(cl + 15);
    }
    h->sock = s;
    h->pos = offset;
    return 0;
}

static ssize_t http_read_some(HttpSrc *h, void *buf, size_t want) {
    if (h->sock < 0) return -1;
    ssize_t n = recv(h->sock, buf, want, 0);
    if (n > 0) h->pos += n;
    return n;
}

static int64_t ds_get_size(void *userdata) {
    HttpSrc *h = userdata;
    return h->size;
}

static ssize_t ds_read_at(void *userdata, off64_t offset, void *buf, size_t size) {
    HttpSrc *h = userdata;
    pthread_mutex_lock(&h->lock);
    if (h->cacheLen == 0 || offset != h->cacheStart ||
        offset >= h->cacheStart + (int64_t)h->cacheLen) {
        // 不在缓存里：重新连接并预读
        if (http_open(h, offset) != 0) { pthread_mutex_unlock(&h->lock); return -1; }
        h->cacheStart = offset;
        h->cacheLen = 0;
        while (h->cacheLen < CACHE_CAP) {
            size_t want = CACHE_CAP - h->cacheLen;
            if (want > READ_CHUNK) want = READ_CHUNK;
            ssize_t n = http_read_some(h, h->cache + h->cacheLen, want);
            if (n <= 0) break;
            h->cacheLen += n;
            if ((size_t)h->cacheLen >= size) break;   // 先满足本次请求
        }
        if (h->cacheLen == 0) { pthread_mutex_unlock(&h->lock); return 0; }
    }
    size_t avail = (size_t)(h->cacheStart + (int64_t)h->cacheLen - offset);
    if (avail > size) avail = size;
    memcpy(buf, h->cache + (offset - h->cacheStart), avail);
    pthread_mutex_unlock(&h->lock);
    return (ssize_t)avail;
}

static void ds_close(void *userdata) {
    HttpSrc *h = userdata;
    if (h->sock >= 0) close(h->sock);
    h->sock = -1;
}

// ---------------- 播放器状态 ----------------

typedef struct {
    ANativeWindow *win;
    char url[2048];
    char host[256];
    char path[1024];
    int port;

    HttpSrc src;
    AMediaDataSource *ds;
    AMediaExtractor *ex;
    AMediaCodec *vc, *ac;
    int vt, at;
    int vw, vh;
    int64_t durationUs;

    AAudioStream *as;
    int arate, ach;

    volatile int running;
    volatile int paused;
    volatile int seekReq;
    int64_t seekToUs;

    int64_t audioClockUs;
    int64_t lastPosUs;
    int started;
    pthread_t thread;
    pthread_mutex_t lock;
} Player;

static Player *P = NULL;

static void parse_url(Player *p) {
    const char *u = p->url;
    if (strncmp(u, "http://", 7) != 0) { LOGE("only http:// supported"); return; }
    u += 7;
    const char *slash = strchr(u, '/');
    const char *colon = strchr(u, ':');
    size_t hostlen;
    if (colon && (!slash || colon < slash)) {
        hostlen = (size_t)(colon - u);
        p->port = atoi(colon + 1);
    } else {
        hostlen = slash ? (size_t)(slash - u) : strlen(u);
        p->port = 80;
    }
    if (hostlen >= sizeof(p->host)) hostlen = sizeof(p->host) - 1;
    memcpy(p->host, u, hostlen);
    p->host[hostlen] = 0;
    if (slash) snprintf(p->path, sizeof(p->path), "%s", slash);
    else snprintf(p->path, sizeof(p->path), "/");
}

static void audio_close(Player *p) {
    if (p->as) { AAudioStream_requestStop(p->as); AAudioStream_close(p->as); p->as = NULL; }
}

static int audio_open(Player *p, AMediaFormat *fmt) {
    int32_t rate = 48000, ch = 2;
    AMediaFormat_getInt32(fmt, AMEDIAFORMAT_KEY_SAMPLE_RATE, &rate);
    AMediaFormat_getInt32(fmt, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &ch);
    p->arate = rate;
    p->ach = ch;
    AAudioStreamBuilder *b = NULL;
    if (AAudio_createStreamBuilder(&b) != AAUDIO_OK) return -1;
    AAudioStreamBuilder_setDirection(b, AAUDIO_DIRECTION_OUTPUT);
    AAudioStreamBuilder_setFormat(b, AAUDIO_FORMAT_PCM_I16);
    AAudioStreamBuilder_setSampleRate(b, rate);
    AAudioStreamBuilder_setChannelCount(b, ch);
    AAudioStreamBuilder_setPerformanceMode(b, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    aaudio_result_t r = AAudioStreamBuilder_openStream(b, &p->as);
    AAudioStreamBuilder_delete(b);
    if (r != AAUDIO_OK) { LOGE("AAudio open failed %d", r); p->as = NULL; return -1; }
    AAudioStream_requestStart(p->as);
    return 0;
}

static int codec_start(Player *p) {
    AMediaFormat *vfmt = AMediaExtractor_getTrackFormat(p->ex, p->vt);
    const char *vmime = NULL;
    AMediaFormat_getString(vfmt, AMEDIAFORMAT_KEY_MIME, &vmime);
    p->vc = AMediaCodec_createDecoderByType(vmime);
    if (!p->vc) { LOGE("no video decoder for %s", vmime ? vmime : "?"); return -1; }
    if (AMediaCodec_configure(p->vc, vfmt, p->win, NULL, 0) != AMEDIA_OK) {
        LOGE("video configure failed");
        return -1;
    }
    AMediaFormat_getInt32(vfmt, AMEDIAFORMAT_KEY_WIDTH, &p->vw);
    AMediaFormat_getInt32(vfmt, AMEDIAFORMAT_KEY_HEIGHT, &p->vh);
    AMediaCodec_start(p->vc);

    if (p->at >= 0) {
        AMediaFormat *afmt = AMediaExtractor_getTrackFormat(p->ex, p->at);
        const char *amime = NULL;
        AMediaFormat_getString(afmt, AMEDIAFORMAT_KEY_MIME, &amime);
        p->ac = AMediaCodec_createDecoderByType(amime);
        if (p->ac) {
            if (AMediaCodec_configure(p->ac, afmt, NULL, NULL, 0) == AMEDIA_OK) {
                AMediaCodec_start(p->ac);
                audio_open(p, afmt);
            } else {
                AMediaCodec_delete(p->ac);
                p->ac = NULL;
            }
        }
        AMediaFormat_delete(afmt);
    }
    AMediaFormat_delete(vfmt);
    return 0;
}

static void codec_stop(Player *p) {
    if (p->vc) { AMediaCodec_stop(p->vc); AMediaCodec_delete(p->vc); p->vc = NULL; }
    if (p->ac) { AMediaCodec_stop(p->ac); AMediaCodec_delete(p->ac); p->ac = NULL; }
    audio_close(p);
}

static void feed_track(Player *p, AMediaCodec *codec, int track) {
    if (!codec) return;
    ssize_t idx = AMediaCodec_dequeueInputBuffer(codec, 5000);
    if (idx < 0) return;
    size_t cap = 0;
    uint8_t *ibuf = AMediaCodec_getInputBuffer(codec, (size_t)idx, &cap);
    if (!ibuf) return;
    ssize_t n = AMediaExtractor_readSampleData(p->ex, ibuf, cap);
    if (n < 0) {
        AMediaCodec_queueInputBuffer(codec, (size_t)idx, 0, 0, 0,
                                     AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM);
        return;
    }
    int64_t pts = AMediaExtractor_getSampleTime(p->ex);
    AMediaCodec_queueInputBuffer(codec, (size_t)idx, 0, (size_t)n, pts, 0);
    AMediaExtractor_advance(p->ex);
}

static void drain_video(Player *p) {
    AMediaCodecBufferInfo info;
    ssize_t idx;
    while ((idx = AMediaCodec_dequeueOutputBuffer(p->vc, &info, 0)) >= 0) {
        if (info.size > 0 || (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM)) {
            // 按音频时钟（没有音频时按墙钟）等到 PTS
            int64_t target = p->ac ? p->audioClockUs : p->audioClockUs;
            int64_t wait = info.presentationTimeUs - target;
            if (wait > 1000) {
                if (wait > 200000) wait = 200000;
                struct timespec ts = {0, wait * 1000};
                nanosleep(&ts, NULL);
            }
            if (info.size > 0) p->lastPosUs = info.presentationTimeUs;
        }
        AMediaCodec_releaseOutputBuffer(p->vc, (size_t)idx, info.size > 0);
        if (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) break;
    }
}

static void drain_audio(Player *p) {
    if (!p->ac) return;
    AMediaCodecBufferInfo info;
    ssize_t idx;
    while ((idx = AMediaCodec_dequeueOutputBuffer(p->ac, &info, 0)) >= 0) {
        if (info.size > 0 && p->as) {
            size_t cap = 0;
            uint8_t *obuf = AMediaCodec_getOutputBuffer(p->ac, (size_t)idx, &cap);
            if (obuf) {
                int32_t frames = info.size / (2 * (p->ach > 0 ? p->ach : 2));
                AAudioStream_write(p->as, obuf + info.offset, frames, 20000000);
                p->audioClockUs = info.presentationTimeUs +
                                  (int64_t)frames * 1000000 / (p->arate > 0 ? p->arate : 48000);
            }
        } else if (p->as) {
            // 没有音频数据时让时钟按墙钟前进，避免视频不动
            p->audioClockUs += 10000;
        }
        if (info.size > 0) p->lastPosUs = info.presentationTimeUs;
        AMediaCodec_releaseOutputBuffer(p->ac, (size_t)idx, false);
        if (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) break;
    }
}

static void *play_thread(void *arg) {
    Player *p = arg;
    p->audioClockUs = 0;
    while (p->running) {
        if (p->paused) {
            if (p->as) AAudioStream_requestPause(p->as);
            usleep(50000);
            continue;
        }
        if (p->as) AAudioStream_requestStart(p->as);

        if (p->seekReq) {
            codec_stop(p);
            AMediaExtractor_seekTo(p->ex, p->seekToUs, AMEDIAEXTRACTOR_SEEK_PREVIOUS_SYNC);
            p->audioClockUs = p->seekToUs;
            for (int i = 0; i < 2; i++) AMediaExtractor_selectTrack(p->ex, i == 0 ? p->vt : p->at);
            codec_start(p);
            p->seekReq = 0;
            p->started = 1;
        }

        feed_track(p, p->vc, p->vt);
        feed_track(p, p->ac, p->at);
        drain_video(p);
        drain_audio(p);
        // 没有音频输出时用墙钟推进
        if (!p->ac) p->audioClockUs += 8000;
    }
    return NULL;
}

// ---------------- JNI ----------------

JNIEXPORT jint JNICALL
Java_com_example_tvplay_NativePlayer_nativeInit(JNIEnv *env, jclass cls,
                                                jobject surface, jstring jurl) {
    if (P) return -1;
    P = calloc(1, sizeof(Player));
    if (!P) return -1;
    pthread_mutex_init(&P->lock, NULL);
    const char *u = (*env)->GetStringUTFChars(env, jurl, NULL);
    snprintf(P->url, sizeof(P->url), "%s", u);
    (*env)->ReleaseStringUTFChars(env, jurl, u);
    P->win = ANativeWindow_fromSurface(env, surface);
    parse_url(P);
    P->src.sock = -1;
    P->src.size = -1;
    snprintf(P->src.host, sizeof(P->src.host), "%s", P->host);
    snprintf(P->src.path, sizeof(P->src.path), "%s", P->path);
    P->src.port = P->port;
    P->src.cache = malloc(CACHE_CAP);
    pthread_mutex_init(&P->src.lock, NULL);

    P->ds = AMediaDataSource_new();
    AMediaDataSource_setUserdata(P->ds, &P->src);
    AMediaDataSource_setReadAt(P->ds, ds_read_at);
    AMediaDataSource_setGetSize(P->ds, ds_get_size);
    AMediaDataSource_setClose(P->ds, ds_close);

    P->ex = AMediaExtractor_new();
    if (AMediaExtractor_setDataSourceCustom(P->ex, P->ds) != AMEDIA_OK) {
        LOGE("setDataSourceCustom failed");
        return -2;
    }
    P->vt = -1;
    P->at = -1;
    size_t ntracks = AMediaExtractor_getTrackCount(P->ex);
    for (size_t i = 0; i < ntracks; i++) {
        AMediaFormat *f = AMediaExtractor_getTrackFormat(P->ex, i);
        const char *mime = NULL;
        AMediaFormat_getString(f, AMEDIAFORMAT_KEY_MIME, &mime);
        if (mime && strncmp(mime, "video/", 6) == 0 && P->vt < 0) P->vt = (int)i;
        else if (mime && strncmp(mime, "audio/", 6) == 0 && P->at < 0) P->at = (int)i;
        AMediaFormat_delete(f);
    }
    if (P->vt < 0) { LOGE("no video track"); return -3; }
    AMediaExtractor_selectTrack(P->ex, P->vt);
    if (P->at >= 0) AMediaExtractor_selectTrack(P->ex, P->at);

    if (codec_start(P) != 0) return -4;
    P->running = 1;
    P->started = 1;
    pthread_create(&P->thread, NULL, play_thread, P);
    LOGI("started %dx%d", P->vw, P->vh);
    return 0;
}

JNIEXPORT void JNICALL
Java_com_example_tvplay_NativePlayer_nativePause(JNIEnv *env, jclass cls, jboolean on) {
    if (P) P->paused = on ? 1 : 0;
}

JNIEXPORT void JNICALL
Java_com_example_tvplay_NativePlayer_nativeSeek(JNIEnv *env, jclass cls, jlong ms) {
    if (P) { P->seekToUs = ms * 1000; P->seekReq = 1; }
}

JNIEXPORT jlong JNICALL
Java_com_example_tvplay_NativePlayer_nativePosition(JNIEnv *env, jclass cls) {
    if (!P) return 0;
    return P->lastPosUs / 1000;
}

JNIEXPORT void JNICALL
Java_com_example_tvplay_NativePlayer_nativeStop(JNIEnv *env, jclass cls) {
    if (!P) return;
    P->running = 0;
    pthread_join(P->thread, NULL);
    codec_stop(P);
    AMediaExtractor_delete(P->ex);
    AMediaDataSource_close(P->ds);
    AMediaDataSource_delete(P->ds);
    if (P->win) ANativeWindow_release(P->win);
    free(P->src.cache);
    free(P);
    P = NULL;
}
