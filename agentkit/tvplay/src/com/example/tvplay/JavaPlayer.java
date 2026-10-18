package com.example.tvplay;

import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.MediaCodec;
import android.media.MediaDataSource;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.view.Surface;

import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.ByteBuffer;

/**
 * JavaPlayer — 自建播放管线（API 23+，兼容这台 Android 8 电视）：
 *   自定义 MediaDataSource（HTTP + 32MB 环形预读缓冲）
 *   → MediaExtractor（系统解封装，MKV/MP4/TS/WebM 全支持）
 *   → MediaCodec 硬解（视频直出 Surface，音频 PCM 给 AudioTrack）
 *
 * 目的：自己控制缓冲与节奏，避免 MediaPlayer 的 "buffer low" 停顿。
 */
public class JavaPlayer {

    // ---------------- HTTP 数据源（环形缓冲 + 后台下载） ----------------

    static class HttpDataSource extends MediaDataSource {
        private static final int RING = 16 * 1024 * 1024;   // 16MB 预读窗口
        private static final int CHUNK = 128 * 1024;

        private final String baseUrl;
        private final byte[] ring = new byte[RING];
        private long ringStart;      // ring 中第一个字节对应的文件偏移
        private int ringLen;
        private long size = -1;

        private long gen = 0;        // 缓冲重定位代数（防止旧下载写错位置）
        private int chunks = 0;
        private int reopens = 0;
        private long fillBytes = 0;
        private long lastLogMs = System.currentTimeMillis();
        private volatile boolean closed;
        private volatile boolean eof;
        private Thread filler;
        private final Object lock = new Object();

        HttpDataSource(String url) throws IOException {
            this.baseUrl = url;
            this.size = probeSize();
            startFiller();
        }

        private long probeSize() throws IOException {
            HttpURLConnection c = (HttpURLConnection) new URL(baseUrl).openConnection();
            c.setRequestProperty("Range", "bytes=0-0");
            c.setConnectTimeout(8000);
            c.setReadTimeout(8000);
            int code = c.getResponseCode();
            long total = -1;
            String cr = c.getHeaderField("Content-Range");
            if (cr != null) {
                int slash = cr.indexOf('/');
                if (slash > 0) total = Long.parseLong(cr.substring(slash + 1).trim());
            } else if (code == 200) {
                total = c.getContentLengthLong();
            }
            c.disconnect();
            android.util.Log.i("tvplay", "size=" + total);
            return total;
        }

        private void startFiller() {
            filler = new Thread(new Runnable() {
                public void run() { fillLoop(); }
            }, "tvplay-http");
            filler.setDaemon(true);
            filler.start();
        }

        private void fillLoop() {
            while (!closed) {
                long from;
                long myGen;
                synchronized (lock) {
                    while (!closed && ringLen >= RING) {
                        try { lock.wait(500); } catch (InterruptedException ignored) { }
                    }
                    if (closed) return;
                    myGen = gen;
                    from = ringStart + ringLen;
                }
                HttpURLConnection c = null;
                try {
                    if (reopens++ < 10) android.util.Log.i("tvplay", "fill open from=" + from + " gen=" + myGen);
                    c = (HttpURLConnection) new URL(baseUrl).openConnection();
                    c.setRequestProperty("Range", "bytes=" + from + "-");
                    c.setConnectTimeout(10000);
                    c.setReadTimeout(20000);
                    InputStream in = c.getInputStream();
                    byte[] buf = new byte[CHUNK];
                    while (!closed) {
                        int need;
                        synchronized (lock) {
                            if (gen != myGen) break;          // 有重定位，丢弃这条连接
                            while (!closed && ringLen >= RING) {
                                try { lock.wait(500); } catch (InterruptedException ignored) { }
                            }
                            if (gen != myGen) break;
                            need = RING - ringLen;
                        }
                        if (closed) break;
                        int n = in.read(buf, 0, Math.min(need, buf.length));
                        if (n < 0) { eof = true; return; }
                        synchronized (lock) {
                            if (gen != myGen) break;
                            int at = (int) ((ringStart + ringLen) % RING);
                            int first = Math.min(n, RING - at);
                            System.arraycopy(buf, 0, ring, at, first);
                            if (first < n) System.arraycopy(buf, first, ring, 0, n - first);
                            ringLen += n;
                            fillBytes += n;
                            long nowMs = System.currentTimeMillis();
                            if (nowMs - lastLogMs > 2000) {
                                android.util.Log.i("tvplay", "fill rate=" + (fillBytes * 1000 / (nowMs - lastLogMs)) + " B/s ring=" + ringLen);
                                fillBytes = 0;
                                lastLogMs = nowMs;
                            }
                            if (chunks++ < 5) android.util.Log.i("tvplay", "fill n=" + n + " ringLen=" + ringLen + " from=" + from);
                            lock.notifyAll();
                        }
                    }
                } catch (Exception e) {
                    if (reopens < 10) android.util.Log.i("tvplay", "fill ex " + e);
                    if (closed) return;
                    try { Thread.sleep(300); } catch (InterruptedException ignored) { }
                } finally {
                    if (c != null) c.disconnect();
                }
            }
        }

        private int calls = 0;

        @Override
        public int readAt(long position, byte[] buffer, int offset, int size) throws IOException {
            if (closed) return -1;
            if (calls++ < 120) android.util.Log.i("tvplay", "readAt " + position + " len=" + size + " rs=" + ringStart + " rl=" + ringLen);
            long deadline = System.currentTimeMillis() + 20000;
            synchronized (lock) {
                while (true) {
                    if (closed) return -1;
                    long end = ringStart + ringLen;
                    if (position < ringStart || position > end) {
                        // 跳读：重定位
                        ringStart = position;
                        ringLen = 0;
                        eof = false;
                        gen++;
                        lock.notifyAll();
                    } else if (position == end && !eof) {
                        // 正好在末尾：等下载
                        try { lock.wait(100); } catch (InterruptedException ignored) { }
                        if (System.currentTimeMillis() > deadline) return -1;
                        continue;
                    }
                    if (position >= ringStart && position < ringStart + ringLen) {
                        // 尽量凑满请求（MediaExtractor 对短读很敏感）
                        while (ringStart + ringLen - position < size && !eof
                                && System.currentTimeMillis() < deadline) {
                            try { lock.wait(100); } catch (InterruptedException ignored) { }
                        }
                        int avail = (int) Math.min(ringStart + ringLen - position, size);
                        int at = (int) ((position) % RING);
                        int first = Math.min(avail, RING - at);
                        System.arraycopy(ring, at, buffer, offset, first);
                        if (first < avail) System.arraycopy(ring, 0, buffer, offset + first, avail - first);
                        if (calls < 120) android.util.Log.i("tvplay", "  -> " + avail);
                        return avail;
                    }
                    if (eof) return -1;
                    try { lock.wait(100); } catch (InterruptedException ignored) { }
                    if (System.currentTimeMillis() > deadline) {
                        if (chunks < 5) android.util.Log.i("tvplay", "readAt timeout pos=" + position + " ringStart=" + ringStart + " ringLen=" + ringLen);
                        return -1;
                    }
                }
            }
        }

        @Override
        public long getSize() {
            return size;
        }

        @Override
        public void close() {
            closed = true;
            synchronized (lock) { lock.notifyAll(); }
        }
    }

    // ---------------- 播放器 ----------------

    private static final long DEQUEUE_TIMEOUT_US = 10000;

    private final String url;
    private final Surface surface;
    private volatile boolean running = true;
    private volatile boolean paused = false;
    private volatile boolean seekReq = false;
    private volatile long seekToUs = 0;
    private volatile long positionUs = 0;

    private MediaExtractor extractor;
    private MediaCodec vc, ac;
    private AudioTrack track;
    private int audioRate = 48000;
    private int audioCh = 2;
    private long audioClockUs = 0;
    private int vt = -1, at = -1;
    private long startWallUs = 0;

    private final boolean noAudio;

    public JavaPlayer(String url, Surface surface, boolean noAudio) {
        this.url = url;
        this.surface = surface;
        this.noAudio = noAudio;
    }

    public void start() {
        Thread t = new Thread(new Runnable() {
            public void run() { loop(); }
        }, "tvplay-java");
        t.setDaemon(true);
        t.start();
    }

    public void pause(boolean on) { paused = on; }

    public boolean toggle() { paused = !paused; return paused; }

    public void seekTo(long ms) {
        seekToUs = ms * 1000;
        seekReq = true;
    }

    public long positionMs() { return positionUs / 1000; }

    public void stop() {
        running = false;
        try { if (extractor != null) extractor.release(); } catch (Exception ignored) { }
    }

    private void loop() {
        try {
            HttpDataSource ds = new HttpDataSource(url);
            extractor = new MediaExtractor();
            extractor.setDataSource(ds);

            vt = -1; at = -1;
            android.util.Log.i("tvplay", "tracks=" + extractor.getTrackCount());
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat f = extractor.getTrackFormat(i);
                String mime = f.getString(MediaFormat.KEY_MIME);
                android.util.Log.i("tvplay", "track " + i + " mime=" + mime);
                if (mime == null) continue;
                if (mime.startsWith("video/") && vt < 0) vt = i;
                else if (mime.startsWith("audio/") && at < 0) at = i;
            }
            if (vt < 0) { android.util.Log.e("tvplay", "no video track"); return; }
            extractor.selectTrack(vt);
            MediaFormat vf = extractor.getTrackFormat(vt);
            String vmime = vf.getString(MediaFormat.KEY_MIME);
            vc = MediaCodec.createDecoderByType(vmime);
            vc.configure(vf, surface, null, 0);
            vc.start();
            android.util.Log.i("tvplay", "video codec started " + vmime);

            if (at >= 0 && !noAudio) {
                extractor.selectTrack(at);
                MediaFormat af = extractor.getTrackFormat(at);
                String amime = af.getString(MediaFormat.KEY_MIME);
                try {
                    ac = MediaCodec.createDecoderByType(amime);
                    ac.configure(af, null, null, 0);
                    ac.start();
                    if (af.containsKey(MediaFormat.KEY_SAMPLE_RATE))
                        audioRate = af.getInteger(MediaFormat.KEY_SAMPLE_RATE);
                    if (af.containsKey(MediaFormat.KEY_CHANNEL_COUNT))
                        audioCh = af.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
                    int minBuf = AudioTrack.getMinBufferSize(audioRate,
                            audioCh == 1 ? AudioFormat.CHANNEL_OUT_MONO : AudioFormat.CHANNEL_OUT_STEREO,
                            AudioFormat.ENCODING_PCM_16BIT);
                    track = new AudioTrack(AudioManager.STREAM_MUSIC, audioRate,
                            audioCh == 1 ? AudioFormat.CHANNEL_OUT_MONO : AudioFormat.CHANNEL_OUT_STEREO,
                            AudioFormat.ENCODING_PCM_16BIT,
                            Math.max(minBuf, 256 * 1024), AudioTrack.MODE_STREAM);
                    track.play();
                } catch (Exception e) {
                    android.util.Log.w("tvplay", "audio disabled: " + e);
                    if (ac != null) { try { ac.release(); } catch (Exception ignored) { } }
                    ac = null;
                    track = null;
                }
            }

            startWallUs = System.nanoTime() / 1000;
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            android.util.Log.i("tvplay", "loop enter vc=" + (vc != null) + " ac=" + (ac != null) + " track=" + (track != null));

            int ticks = 0;
            while (running) {
                if ((ticks++ % 50) == 0)
                    android.util.Log.i("tvplay", "tick fed=" + fedCount + " out=" + outCount + " clock=" + audioClockUs);
                if (paused) {
                    if (track != null) track.pause();
                    Thread.sleep(30);
                    continue;
                }
                if (track != null) track.play();

                if (seekReq) {
                    seekReq = false;
                    extractor.seekTo(seekToUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC);
                    if (vc != null) vc.flush();
                    if (ac != null) ac.flush();
                    if (track != null) track.flush();
                    audioClockUs = seekToUs;
                    startWallUs = System.nanoTime() / 1000 - seekToUs;
                }

                feedAll();
                drainVideo(info);
                drainAudio(info);
                positionUs = audioClockUs > positionUs ? audioClockUs : positionUs;
            }
        } catch (Exception e) {
            android.util.Log.e("tvplay", "player error: " + e, e);
        } finally {
            try { if (vc != null) { vc.stop(); vc.release(); } } catch (Exception ignored) { }
            try { if (ac != null) { ac.stop(); ac.release(); } } catch (Exception ignored) { }
            try { if (track != null) { track.stop(); track.release(); } } catch (Exception ignored) { }
            try { if (extractor != null) extractor.release(); } catch (Exception ignored) { }
        }
    }

    private final ByteBuffer scratch = ByteBuffer.allocateDirect(2 * 1024 * 1024);
    private int fedCount = 0;

    private void feedAll() {
        int n;
        try {
            scratch.clear();
            n = extractor.readSampleData(scratch, 0);
        } catch (Exception e) {
            if (fedCount < 3) android.util.Log.i("tvplay", "readSampleData ex " + e);
            return;
        }
        if (n < 0) {
            if (fedCount < 3) android.util.Log.i("tvplay", "eos n=" + n);
            try {
                int i1 = vc.dequeueInputBuffer(0);
                if (i1 >= 0) vc.queueInputBuffer(i1, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                if (ac != null) {
                    int i2 = ac.dequeueInputBuffer(0);
                    if (i2 >= 0) ac.queueInputBuffer(i2, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                }
            } catch (Exception ignored) { }
            return;
        }
        int track = extractor.getSampleTrackIndex();
        long pts = extractor.getSampleTime();
        MediaCodec codec = track == vt ? vc : (track == at ? ac : null);
        if (codec != null) {
            try {
                int idx = codec.dequeueInputBuffer(10000);
                if (idx < 0) {
                    if (fedCount < 3) android.util.Log.i("tvplay", "no input buf");
                    return;
                }
                ByteBuffer ib = codec.getInputBuffer(idx);
                if (ib == null) return;
                ib.clear();
                scratch.position(0);
                scratch.limit(n);
                ib.put(scratch);
                codec.queueInputBuffer(idx, 0, n, pts, 0);
                extractor.advance();
                fedCount++;
                if (fedCount % 100 == 1) android.util.Log.i("tvplay", "fed " + fedCount + " track=" + track + " pts=" + pts);
            } catch (Exception ignored) { }
        }
    }

    private int outCount = 0;

    private void drainVideo(MediaCodec.BufferInfo info) {
        if (vc == null) return;
        try {
            while (true) {
                int idx = vc.dequeueOutputBuffer(info, 0);
                if (idx == MediaCodec.INFO_TRY_AGAIN_LATER) return;
                if (idx < 0) continue;
                if (info.size > 0) {
                    if (outCount++ < 5) android.util.Log.i("tvplay", "vout pts=" + info.presentationTimeUs + " clock=" + audioClockUs);
                    long target = ac != null ? audioClockUs : (System.nanoTime() / 1000 - startWallUs);
                    long waitUs = info.presentationTimeUs - target;
                    if (waitUs > 200000) waitUs = 200000;
                    if (waitUs > 1000) Thread.sleep(waitUs / 1000);
                    positionUs = info.presentationTimeUs;
                }
                vc.releaseOutputBuffer(idx, info.size > 0);
                if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return;
            }
        } catch (Exception ignored) { }
    }

    private void drainAudio(MediaCodec.BufferInfo info) {
        if (ac == null) return;
        try {
            while (true) {
                int idx = ac.dequeueOutputBuffer(info, 0);
                if (idx == MediaCodec.INFO_TRY_AGAIN_LATER) return;
                if (idx < 0) continue;
                if (info.size > 0) {
                    ByteBuffer out = ac.getOutputBuffer(idx);
                    if (out != null && track != null) {
                        out.position(info.offset);
                        out.limit(info.offset + info.size);
                        byte[] pcm = new byte[info.size];
                        out.get(pcm);
                        track.write(pcm, 0, pcm.length);
                        int frames = info.size / (2 * Math.max(1, audioCh));
                        audioClockUs = info.presentationTimeUs
                                + (long) frames * 1000000L / Math.max(1, audioRate);
                        positionUs = info.presentationTimeUs;
                    }
                }
                ac.releaseOutputBuffer(idx, false);
                if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return;
            }
        } catch (Exception ignored) { }
    }
}
