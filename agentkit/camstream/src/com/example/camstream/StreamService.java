package com.example.camstream;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.graphics.ImageFormat;
import android.graphics.Rect;
import android.graphics.YuvImage;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.Image;
import android.media.ImageReader;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.SystemClock;
import android.util.Size;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Collections;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;

public class StreamService extends Service {
    private static final int PORT = 8080;
    private static final int AUDIO_RATE = 16000;
    private static final int MAX_FPS = 10;
    private static final int JPEG_QUALITY = 92;
    private volatile int streamW = 0, streamH = 0;

    private HandlerThread bgThread;
    private Handler bg;
    private PowerManager.WakeLock wl;

    private volatile byte[] latestJpeg;
    private volatile long jpegSeq;
    private volatile long lastConv;
    private final LinkedBlockingQueue<byte[]> audioQ = new LinkedBlockingQueue<byte[]>(32);

    private volatile int curFacing = -1;      // LENS_FACING_BACK / FRONT
    private final Object camLock = new Object();
    private CameraDevice cam;
    private CameraCaptureSession sess;
    private ImageReader reader;
    private AudioRecord ar;
    private volatile boolean running = true;

    @Override public void onCreate() {
        super.onCreate();
        bgThread = new HandlerThread("cam-bg");
        bgThread.start();
        bg = new Handler(bgThread.getLooper());
        PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
        wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "camstream:wl");
        wl.acquire();
        startNotif();
        startHttp();
        bg.post(new Runnable() { public void run() { switchCamera(CameraCharacteristics.LENS_FACING_BACK); } });
        startAudio();
    }

    private void startNotif() {
        String ch = "cam";
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel c = new NotificationChannel(ch, "CamStream", NotificationManager.IMPORTANCE_LOW);
            ((NotificationManager) getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(c);
        }
        Notification.Builder b = (Build.VERSION.SDK_INT >= 26)
            ? new Notification.Builder(this, ch) : new Notification.Builder(this);
        Notification n = b.setContentTitle("CamStream 运行中")
            .setContentText(":" + PORT + "  /video  /audio")
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setOngoing(true).build();
        startForeground(1, n);
    }

    private void startHttp() {
        new Thread(new Runnable() { public void run() {
            try {
                ServerSocket ss = new ServerSocket(PORT);
                while (running) {
                    final Socket s = ss.accept();
                    new Thread(new Runnable() { public void run() { handle(s); } }).start();
                }
            } catch (Exception e) { }
        }}).start();
    }

    private void handle(Socket s) {
        try {
            s.setSoTimeout(5000);
            InputStream in = s.getInputStream();
            StringBuilder sb = new StringBuilder();
            int c;
            while ((c = in.read()) != -1 && c != '\n' && sb.length() < 1024) sb.append((char) c);
            String[] parts = sb.toString().split(" ");
            String path = parts.length >= 2 ? parts[1] : "/";
            String query = "";
            int q = path.indexOf('?');
            if (q >= 0) { query = path.substring(q + 1); path = path.substring(0, q); }
            OutputStream out = s.getOutputStream();

            if (path.startsWith("/info")) {
                String json = cameraInfoJson();
                out.write(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n" + json).getBytes());
                out.flush();
                return;
            }
            if (query.contains("cam=")) {
                int facing = query.contains("cam=front") ? CameraCharacteristics.LENS_FACING_FRONT
                                                          : CameraCharacteristics.LENS_FACING_BACK;
                switchCamera(facing);
            }

            if (path.startsWith("/video")) {
                out.write(("HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\n" +
                        "Cache-Control: no-cache\r\nConnection: close\r\n\r\n").getBytes());
                long last = -1;
                while (running) {
                    if (jpegSeq == last) { Thread.sleep(10); continue; }
                    last = jpegSeq;
                    byte[] j = latestJpeg;
                    if (j == null) { Thread.sleep(50); continue; }
                    out.write(("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: " + j.length + "\r\n\r\n").getBytes());
                    out.write(j);
                    out.write("\r\n".getBytes());
                    out.flush();
                }
            } else if (path.startsWith("/audio")) {
                out.write(("HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\nConnection: close\r\n\r\n").getBytes());
                out.write(wavHeader());
                out.flush();
                while (running) {
                    byte[] b = audioQ.poll(1, TimeUnit.SECONDS);
                    if (b != null) { out.write(b); out.flush(); }
                }
            } else {
                String html = "<html><body><h2>CamStream</h2>" +
                    "<p>视频: <a href='/video'>/video</a> (MJPEG)</p>" +
                    "<p>音频: <a href='/audio'>/audio</a> (WAV 16k mono)</p></body></html>";
                out.write(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n" + html).getBytes());
                out.flush();
            }
        } catch (Exception e) {
        } finally {
            try { s.close(); } catch (Exception e) { }
        }
    }

    private byte[] wavHeader() {
        int ch = 1, bits = 16;
        int byteRate = AUDIO_RATE * ch * bits / 8;
        long dataLen = 0x7fffffffL;
        ByteBuffer b = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
        b.put("RIFF".getBytes()); b.putInt((int) (36 + dataLen)); b.put("WAVE".getBytes());
        b.put("fmt ".getBytes()); b.putInt(16); b.putShort((short) 1); b.putShort((short) ch);
        b.putInt(AUDIO_RATE); b.putInt(byteRate); b.putShort((short) (ch * bits / 8)); b.putShort((short) bits);
        b.put("data".getBytes()); b.putInt((int) dataLen);
        return b.array();
    }

    private String findCameraId(int facing) {
        try {
            CameraManager cm = (CameraManager) getSystemService(CAMERA_SERVICE);
            for (String cid : cm.getCameraIdList()) {
                Integer f = cm.getCameraCharacteristics(cid).get(CameraCharacteristics.LENS_FACING);
                if (f != null && f == facing) return cid;
            }
        } catch (Exception e) { }
        return null;
    }

    private String cameraInfoJson() {
        StringBuilder sb = new StringBuilder("{\"current\":");
        sb.append(curFacing == CameraCharacteristics.LENS_FACING_FRONT ? "\"front\""
                 : curFacing == CameraCharacteristics.LENS_FACING_BACK ? "\"back\"" : "\"none\"");
        sb.append(",\"size\":\"").append(streamW).append("x").append(streamH).append("\"");
        sb.append(",\"cameras\":[");
        try {
            CameraManager cm = (CameraManager) getSystemService(CAMERA_SERVICE);
            boolean first = true;
            for (String cid : cm.getCameraIdList()) {
                Integer f = cm.getCameraCharacteristics(cid).get(CameraCharacteristics.LENS_FACING);
                String name = (f != null && f == CameraCharacteristics.LENS_FACING_FRONT) ? "front"
                            : (f != null && f == CameraCharacteristics.LENS_FACING_BACK) ? "back" : "other";
                if (!first) sb.append(",");
                sb.append("{\"id\":\"").append(cid).append("\",\"facing\":\"").append(name).append("\"}");
                first = false;
            }
        } catch (Exception e) { }
        sb.append("],\"sizes\":[");
        try {
            CameraManager cm2 = (CameraManager) getSystemService(CAMERA_SERVICE);
            String cid = findCameraId(curFacing);
            if (cid != null) {
                StreamConfigurationMap m = cm2.getCameraCharacteristics(cid)
                        .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
                boolean f2 = true;
                for (Size sz : m.getOutputSizes(ImageFormat.YUV_420_888)) {
                    if (!f2) sb.append(",");
                    sb.append("\"").append(sz.getWidth()).append("x").append(sz.getHeight()).append("\"");
                    f2 = false;
                }
            }
        } catch (Exception e) { }
        sb.append("]}");
        return sb.toString();
    }

    private void switchCamera(int facing) {
        synchronized (camLock) {
            if (curFacing == facing && cam != null) return;
            closeCameraLocked();
            openCameraLocked(facing);
        }
    }

    private void closeCameraLocked() {
        try { if (sess != null) sess.close(); } catch (Exception e) { }
        try { if (cam != null) cam.close(); } catch (Exception e) { }
        try { if (reader != null) reader.close(); } catch (Exception e) { }
        sess = null; cam = null; reader = null; curFacing = -1;
    }

    private void openCameraLocked(int facing) {
        final String id = findCameraId(facing);
        if (id == null) return;
        try {
            CameraManager cm = (CameraManager) getSystemService(CAMERA_SERVICE);
            CameraCharacteristics cc = cm.getCameraCharacteristics(id);
            StreamConfigurationMap map = cc.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            Size[] sizes = map.getOutputSizes(ImageFormat.YUV_420_888);
            // 不裁不缩：取传感器原生 4:3 的最大尺寸（≤1920 宽，保证 MJPEG 流畅）
            Size pick = sizes[0];
            for (Size sz : sizes) {
                if (sz.getWidth() * 3 == sz.getHeight() * 4 && sz.getWidth() <= 1920) { pick = sz; break; }
            }
            if (pick.getWidth() > 1920) {
                pick = sizes[0];
                for (Size sz : sizes) {
                    if (sz.getWidth() <= 1920) { pick = sz; break; }
                }
            }
            final int W = pick.getWidth(), H = pick.getHeight();
            streamW = W; streamH = H;
            android.util.Log.i("camstream", "stream size " + W + "x" + H);
            final int useFacing = facing;
            reader = ImageReader.newInstance(W, H, ImageFormat.YUV_420_888, 2);
            reader.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
                public void onImageAvailable(ImageReader r) {
                    long now = SystemClock.elapsedRealtime();
                    if (now - lastConv < 1000 / MAX_FPS) {
                        Image im0 = r.acquireNextImage();
                        if (im0 != null) im0.close();
                        return;
                    }
                    Image img = null;
                    try { img = r.acquireLatestImage(); } catch (Exception e) { return; }
                    if (img == null) return;
                    try {
                        byte[] nv21 = toNv21(img, W, H);
                        YuvImage yu = new YuvImage(nv21, ImageFormat.NV21, W, H, null);
                        ByteArrayOutputStream bo = new ByteArrayOutputStream();
                        yu.compressToJpeg(new Rect(0, 0, W, H), JPEG_QUALITY, bo);
                        latestJpeg = bo.toByteArray();
                        jpegSeq++;
                        lastConv = now;
                    } catch (Throwable t) {
                    } finally { img.close(); }
                }
            }, bg);

            cm.openCamera(id, new CameraDevice.StateCallback() {
                public void onOpened(CameraDevice c) {
                    cam = c;
                    curFacing = useFacing;
                    try {
                        c.createCaptureSession(Collections.singletonList(reader.getSurface()),
                            new CameraCaptureSession.StateCallback() {
                                public void onConfigured(CameraCaptureSession s2) {
                                    sess = s2;
                                    try { s2.setRepeatingRequest(req(), null, bg); } catch (Exception e) { }
                                }
                                public void onConfigureFailed(CameraCaptureSession s2) { }
                            }, bg);
                    } catch (Exception e) { }
                }
                public void onDisconnected(CameraDevice c) { c.close(); cam = null; curFacing = -1; }
                public void onError(CameraDevice c, int e) { c.close(); cam = null; curFacing = -1; }
            }, bg);
        } catch (Exception e) { }
    }

    private CaptureRequest req() throws Exception {
        CaptureRequest.Builder b = cam.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
        b.addTarget(reader.getSurface());
        b.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO);
        b.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON);
        b.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO);
        return b.build();
    }

    private byte[] toNv21(Image img, int W, int H) {
        Image.Plane[] p = img.getPlanes();
        byte[] out = new byte[W * H * 3 / 2];
        ByteBuffer yb = p[0].getBuffer();
        int ys = p[0].getRowStride(), yp = p[0].getPixelStride();
        int idx = 0;
        for (int y = 0; y < H; y++) {
            int base = y * ys;
            for (int x = 0; x < W; x++) out[idx++] = yb.get(base + x * yp);
        }
        ByteBuffer ub = p[1].getBuffer(), vb = p[2].getBuffer();
        int us = p[1].getRowStride(), up = p[1].getPixelStride();
        int vs = p[2].getRowStride(), vp = p[2].getPixelStride();
        for (int y = 0; y < H / 2; y++) {
            for (int x = 0; x < W / 2; x++) {
                out[idx++] = vb.get(y * vs + x * vp);
                out[idx++] = ub.get(y * us + x * up);
            }
        }
        return out;
    }

    private void startAudio() {
        new Thread(new Runnable() { public void run() {
            try {
                int min = AudioRecord.getMinBufferSize(AUDIO_RATE,
                        AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT);
                int bufSize = Math.max(min, 8192);
                ar = new AudioRecord(MediaRecorder.AudioSource.MIC, AUDIO_RATE,
                        AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufSize);
                if (ar.getState() != AudioRecord.STATE_INITIALIZED) return;
                ar.startRecording();
                byte[] buf = new byte[4096];
                while (running) {
                    int n = ar.read(buf, 0, buf.length);
                    if (n > 0) {
                        byte[] copy = new byte[n];
                        System.arraycopy(buf, 0, copy, 0, n);
                        if (!audioQ.offer(copy)) { audioQ.poll(); audioQ.offer(copy); }
                    }
                }
            } catch (Exception e) { }
        }}).start();
    }

    @Override public void onDestroy() {
        running = false;
        synchronized (camLock) { closeCameraLocked(); }
        try { if (ar != null) { ar.stop(); ar.release(); } } catch (Exception e) { }
        if (wl != null && wl.isHeld()) wl.release();
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent i) { return null; }
}
