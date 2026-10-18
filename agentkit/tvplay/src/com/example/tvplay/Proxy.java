package com.example.tvplay;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URL;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;

/**
 * 本地预读代理：MediaPlayer 连 127.0.0.1，本代理从远端按 Range 拉流，
 * 先攒够 PREBUF 字节再往播放器写，之后持续读满 CHUNKS*CHUNK 的窗口。
 * 目的：用本地大缓冲吃掉 2.4G WiFi 的抖动，避免 NuPlayer "buffer low"。
 */
public class Proxy {
    private static final int CHUNK = 256 * 1024;      // 每次读 256KB
    private static final int CHUNKS = 128;            // 窗口 32MB
    private static final int PREBUF_CHUNKS = 16;      // 起播前攒 4MB
    private static final long PREBUF_WAIT_MS = 6000;  // 攒不够也最多等 6 秒

    private final ServerSocket server;
    private final String remote;
    private volatile boolean running = true;

    public Proxy(String remoteUrl) throws IOException {
        this.remote = remoteUrl;
        this.server = new ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"));
        Thread t = new Thread(new Runnable() {
            public void run() { acceptLoop(); }
        }, "tvplay-proxy");
        t.setDaemon(true);
        t.start();
    }

    public String url() {
        return "http://127.0.0.1:" + server.getLocalPort() + "/stream";
    }

    public void stop() {
        running = false;
        try { server.close(); } catch (IOException ignored) { }
    }

    private void acceptLoop() {
        while (running) {
            try {
                Socket s = server.accept();
                final Socket conn = s;
                Thread t = new Thread(new Runnable() {
                    public void run() { handle(conn); }
                }, "tvplay-conn");
                t.setDaemon(true);
                t.start();
            } catch (IOException e) {
                if (!running) return;
            }
        }
    }

    private void handle(Socket s) {
        try {
            s.setSoTimeout(20000);
            InputStream cin = s.getInputStream();
            String range = null;
            StringBuilder head = new StringBuilder();
            int c;
            while ((c = cin.read()) != -1) {
                head.append((char) c);
                if (head.length() > 4096) break;
                if (head.toString().endsWith("\r\n\r\n")) break;
            }
            for (String line : head.toString().split("\r\n")) {
                if (line.toLowerCase().startsWith("range:")) {
                    range = line.substring(line.indexOf(':') + 1).trim();
                }
            }

            HttpURLConnection conn = (HttpURLConnection) new URL(remote).openConnection();
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(20000);
            if (range != null) conn.setRequestProperty("Range", range);
            int code = conn.getResponseCode();
            long len = conn.getContentLengthLong();
            String cr = conn.getHeaderField("Content-Range");

            OutputStream out = s.getOutputStream();
            StringBuilder resp = new StringBuilder("HTTP/1.1 " + code + (code == 206 ? " Partial Content" : " OK") + "\r\n");
            resp.append("Content-Type: application/octet-stream\r\n");
            if (len >= 0) resp.append("Content-Length: ").append(len).append("\r\n");
            if (cr != null) resp.append("Content-Range: ").append(cr).append("\r\n");
            resp.append("Accept-Ranges: bytes\r\nConnection: close\r\n\r\n");
            out.write(resp.toString().getBytes("ISO-8859-1"));
            out.flush();

            ArrayBlockingQueue<byte[]> q = new ArrayBlockingQueue<>(CHUNKS);
            InputStream in = conn.getInputStream();
            final boolean[] eof = {false};
            Thread reader = new Thread(new Runnable() {
                public void run() {
                    try {
                        byte[] buf = new byte[CHUNK];
                        while (running) {
                            int n = in.read(buf);
                            if (n < 0) break;
                            byte[] b = new byte[n];
                            System.arraycopy(buf, 0, b, 0, n);
                            q.put(b);
                        }
                    } catch (Exception ignored) {
                    } finally {
                        eof[0] = true;
                    }
                }
            }, "tvplay-reader");
            reader.setDaemon(true);
            reader.start();

            // 预缓冲：攒够 PREBUF 再开始写（最多等 PREBUF_WAIT_MS）
            long t0 = System.currentTimeMillis();
            while (q.size() < PREBUF_CHUNKS && !eof[0]
                    && System.currentTimeMillis() - t0 < PREBUF_WAIT_MS) {
                Thread.sleep(50);
            }

            while (running) {
                byte[] b = q.poll(1, TimeUnit.SECONDS);
                if (b == null) {
                    if (eof[0] && q.isEmpty()) break;
                    continue;
                }
                out.write(b);
                out.flush();
            }
        } catch (Exception ignored) {
        } finally {
            try { s.close(); } catch (IOException ignored) { }
        }
    }
}
