package com.example.tvplay;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URL;
import java.util.HashMap;
import java.util.Map;

/**
 * 本地缓存代理：所有播放器的 Range 请求共用同一条顺序下载流。
 *
 * 旧实现每个 Range 请求各开一条远端连接；NuPlayer 会并发发很多 Range，
 * 在 2.4G/5G WiFi 上互相抢带宽，导致 buffer low。这里改成：
 *   一条后台下载流 → 64MB 环形缓存 → 任意 Range 都从缓存读
 * 缓存满了只丢弃“所有活跃读请求之前”的数据，避免重复下载。
 */
public class Proxy {
    private static final int RING = 64 * 1024 * 1024;   // 64MB 环形缓存
    private static final int CHUNK = 256 * 1024;
    private static final int KEEP = 32 * 1024 * 1024;   // 保留 32MB 历史，避免小幅回退清空缓存
    private static final int PREBUF = 12 * 1024 * 1024; // 起播前缓存 12MB，其余边播边缓存

    private final ServerSocket server;
    private final String remote;
    private volatile long total = -1;
    private volatile Cache cache;
    private volatile boolean running = true;

    public Proxy(String remoteUrl) throws IOException {
        android.util.Log.i("tvplay", "proxy init " + remoteUrl);
        this.remote = remoteUrl;
        this.server = new ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"));
        android.util.Log.i("tvplay", "proxy port=" + server.getLocalPort());
        Thread t = new Thread(new Runnable() {
            public void run() { init(); }
        }, "tvplay-proxy-init");
        t.setDaemon(true);
        t.start();
    }

    private void init() {
        try {
            total = probeSize();
            android.util.Log.i("tvplay", "proxy total=" + total);
            Cache c = new Cache(total);
            cache = c;
            c.start();
            acceptLoop();
        } catch (IOException e) {
            android.util.Log.e("tvplay", "proxy init failed", e);
        }
    }

    public String url() {
        return "http://127.0.0.1:" + server.getLocalPort() + "/stream";
    }

    public void stop() {
        running = false;
        Cache c = cache;
        if (c != null) c.close();
        try { server.close(); } catch (IOException ignored) { }
    }

    private long probeSize() throws IOException {
        android.util.Log.i("tvplay", "probe size start");
        HttpURLConnection c = (HttpURLConnection) new URL(remote).openConnection();
        c.setRequestProperty("Range", "bytes=0-0");
        c.setConnectTimeout(8000);
        c.setReadTimeout(8000);
        int code = c.getResponseCode();
        long size = -1;
        String cr = c.getHeaderField("Content-Range");
        if (cr != null) {
            int slash = cr.indexOf('/');
            if (slash > 0) {
                try { size = Long.parseLong(cr.substring(slash + 1).trim()); }
                catch (Exception ignored) { }
            }
        } else if (code == 200) {
            size = c.getContentLengthLong();
        }
        c.disconnect();
        android.util.Log.i("tvplay", "proxy size=" + size);
        return size;
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
        int rid = -1;
        boolean registered = false;
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

            Cache cc = cache;
            if (cc == null) {
                OutputStream out = s.getOutputStream();
                out.write("HTTP/1.1 503 Not Ready\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                        .getBytes("ISO-8859-1"));
                out.flush();
                return;
            }
            long sz = total;
            long start = 0, end = sz > 0 ? sz - 1 : Long.MAX_VALUE;
            boolean partial = false;
            if (range != null) {
                long[] span = parseRange(range, sz);
                if (span == null) {
                    OutputStream out = s.getOutputStream();
                    String resp = "HTTP/1.1 416 Range Not Satisfiable\r\n"
                            + (sz > 0 ? "Content-Range: bytes */" + sz + "\r\n" : "")
                            + "Content-Length: 0\r\nConnection: close\r\n\r\n";
                    out.write(resp.getBytes("ISO-8859-1"));
                    out.flush();
                    return;
                }
                start = span[0];
                end = span[1];
                partial = true;
            }
            OutputStream out = s.getOutputStream();
            StringBuilder resp = new StringBuilder("HTTP/1.1 " + (partial ? "206 Partial Content" : "200 OK") + "\r\n");
            resp.append("Content-Type: ").append(mimeFor(remote)).append("\r\n");
            resp.append("Accept-Ranges: bytes\r\n");
            resp.append("Content-Length: ").append(end - start + 1).append("\r\n");
            if (partial)
                resp.append("Content-Range: bytes ").append(start).append('-').append(end)
                        .append('/').append(sz > 0 ? sz : '*').append("\r\n");
            resp.append("Connection: close\r\n\r\n");
            out.write(resp.toString().getBytes("ISO-8859-1"));
            out.flush();

            rid = cache.beginRead(start);
            registered = true;
            byte[] buf = new byte[CHUNK];
            long pos = start;
            while (running && pos <= end) {
                if (pos < cc.base) {
                    // 数据已被更快的读者丢弃：从远端直接补完，避免截断流
                    streamDirect(pos, end, out);
                    pos = end + 1;
                    break;
                }
                int want = (int) Math.min(buf.length, end - pos + 1);
                int n = cc.readAt(pos, buf, 0, want);
                if (n <= 0) {
                    if (pos < cc.base) {
                        streamDirect(pos, end, out);
                        pos = end + 1;
                    }
                    break;
                }
                out.write(buf, 0, n);
                out.flush();
                pos += n;
                cc.updateRead(rid, pos);
            }
            android.util.Log.i("tvplay", "proxy served " + start + "-" + (pos - 1)
                    + " (cache base=" + cc.base + " len=" + cc.len + ")");
        } catch (Exception ignored) {
        } finally {
            if (registered && cache != null) cache.endRead(rid);
            try { s.close(); } catch (IOException ignored) { }
        }
    }

    private void streamDirect(long start, long end, OutputStream out) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(remote).openConnection();
        c.setConnectTimeout(10000);
        c.setReadTimeout(20000);
        c.setRequestProperty("Accept-Encoding", "identity");
        c.setRequestProperty("Range", "bytes=" + start + "-" + end);
        InputStream in = c.getInputStream();
        byte[] buf = new byte[CHUNK];
        long left = end - start + 1;
        try {
            while (left > 0 && running) {
                int n = in.read(buf, 0, (int) Math.min(buf.length, left));
                if (n < 0) break;
                out.write(buf, 0, n);
                out.flush();
                left -= n;
            }
        } finally {
            try { in.close(); } catch (IOException ignored) { }
            c.disconnect();
        }
    }

    private static long[] parseRange(String r, long size) {
        // bytes=start-end | bytes=start- | bytes=-suffix
        if (!r.startsWith("bytes=")) return null;
        String v = r.substring(6).trim();
        int dash = v.indexOf('-');
        if (dash < 0 || size <= 0) return null;
        try {
            String a = v.substring(0, dash).trim();
            String b = v.substring(dash + 1).trim();
            long start, end;
            if (a.length() == 0) {                 // suffix
                long n = Long.parseLong(b);
                if (n <= 0) return null;
                start = Math.max(0, size - n);
                end = size - 1;
            } else {
                start = Long.parseLong(a);
                end = b.length() == 0 ? size - 1 : Math.min(Long.parseLong(b), size - 1);
            }
            if (start >= size || start > end) return null;
            return new long[] { start, end };
        } catch (Exception e) {
            return null;
        }
    }

    private static String mimeFor(String url) {
        String u = url.toLowerCase();
        int q = u.indexOf('?');
        if (q >= 0) u = u.substring(0, q);
        if (u.endsWith(".mkv")) return "video/x-matroska";
        if (u.endsWith(".mp4") || u.endsWith(".m4v")) return "video/mp4";
        if (u.endsWith(".ts")) return "video/mp2t";
        if (u.endsWith(".webm")) return "video/webm";
        if (u.endsWith(".avi")) return "video/x-msvideo";
        if (u.endsWith(".mov")) return "video/quicktime";
        return "application/octet-stream";
    }

    // ------------------------------------------------------------------

    private class Cache {
        final long size;
        final byte[] ring = new byte[RING];
        long base = 0;
        int len = 0;
        long gen = 0;
        long fetched = 0;
        volatile boolean prebufDone = false;
        boolean eof = false;
        boolean closed = false;
        final Object lock = new Object();
        final Map<Integer, long[]> active = new HashMap<>();
        int nextId = 1;
        Thread filler;

        Cache(long size) { this.size = size; }

        void start() {
            filler = new Thread(new Runnable() {
                public void run() { fillLoop(); }
            }, "tvplay-cache");
            filler.setDaemon(true);
            filler.start();
        }

        void close() {
            synchronized (lock) {
                closed = true;
                lock.notifyAll();
            }
        }

        int beginRead(long pos) {
            synchronized (lock) {
                int id = nextId++;
                active.put(id, new long[] { pos, System.currentTimeMillis() });
                lock.notifyAll();
                return id;
            }
        }

        void updateRead(int id, long pos) {
            synchronized (lock) {
                long[] cur = active.get(id);
                if (cur != null) {
                    cur[0] = pos;
                    cur[1] = System.currentTimeMillis();
                    lock.notifyAll();
                }
            }
        }

        void endRead(int id) {
            synchronized (lock) {
                active.remove(id);
                lock.notifyAll();
            }
        }

        private long discardTarget() {
            // 只丢弃所有活跃读者当前位置之前的数据（保留 8MB 余量）
            long min = Long.MAX_VALUE;
            long now = System.currentTimeMillis();
            for (long[] p : active.values()) {
                if (now - p[1] <= 10000 && p[0] < min) min = p[0];
            }
            if (min == Long.MAX_VALUE) return base + len - KEEP;
            return min - KEEP;
        }

        private void makeRoom() {
            if (!prebufDone) return;
            while (!closed && len >= RING) {
                long target = discardTarget();
                long advance = target - base;
                if (advance > 0) {
                    if (advance > len) advance = len;
                    base += advance;
                    len -= advance;
                    android.util.Log.i("tvplay", "cache room base=" + base + " len=" + len
                            + " fetched=" + fetched);
                    lock.notifyAll();
                } else {
                    try { lock.wait(200); } catch (InterruptedException ignored) { }
                }
            }
        }

        void reset(long pos) {
            synchronized (lock) {
                base = pos;
                len = 0;
                gen++;
                eof = false;
                prebufDone = false;
                lock.notifyAll();
            }
        }

        int readAt(long pos, byte[] out, int off, int want) throws IOException {
            long deadline = System.currentTimeMillis() + 30000;
            synchronized (lock) {
                long preWait = System.currentTimeMillis();
                while (!closed && !prebufDone && !eof
                        && System.currentTimeMillis() - preWait < 90000) {
                    try { lock.wait(100); } catch (InterruptedException ignored) { }
                }
                while (!closed) {
                    if (pos < base) return -1;
                    long end = base + len;
                    if (pos >= base && pos < end) {
                        int avail = (int) Math.min(end - pos, want);
                        int at = (int) (pos % RING);
                        int first = Math.min(avail, RING - at);
                        System.arraycopy(ring, at, out, off, first);
                        if (first < avail)
                            System.arraycopy(ring, 0, out, off + first, avail - first);
                        return avail;
                    }
                    if (eof && pos >= base + len) return -1;
                    long wt = System.currentTimeMillis();
                    try { lock.wait(100); } catch (InterruptedException ignored) { }
                    if (System.currentTimeMillis() - wt > 1000)
                        android.util.Log.i("tvplay", "cache wait pos=" + pos + " base=" + base
                                + " len=" + len + " fetched=" + fetched);
                    if (System.currentTimeMillis() > deadline) return -1;
                }
                return -1;
            }
        }

        private void fillLoop() {
            while (true) {
                long from;
                long myGen;
                synchronized (lock) {
                    makeRoom();
                    if (closed) return;
                    myGen = gen;
                    from = base + len;
                    if (size > 0 && from >= size) {
                        eof = true;
                        lock.notifyAll();
                        return;
                    }
                }
                HttpURLConnection c = null;
                try {
                    c = (HttpURLConnection) new URL(remote).openConnection();
                    c.setConnectTimeout(10000);
                    c.setReadTimeout(20000);
                    c.setRequestProperty("Accept-Encoding", "identity");
                    c.setRequestProperty("Range", "bytes=" + from + "-");
                    InputStream in = c.getInputStream();
                    byte[] buf = new byte[CHUNK];
                    while (true) {
                        int need;
                        synchronized (lock) {
                            if (closed) return;
                            if (gen != myGen) break;
                            makeRoom();
                            if (gen != myGen) break;
                            need = RING - len;
                            if (size > 0 && base + len >= size) {
                                eof = true;
                                lock.notifyAll();
                                return;
                            }
                            if (need > CHUNK) need = CHUNK;
                        }
                        int n = in.read(buf, 0, need);
                        if (n < 0) {
                            synchronized (lock) { eof = true; lock.notifyAll(); }
                            return;
                        }
                        synchronized (lock) {
                            if (gen != myGen) break;
                            int at = (int) ((base + len) % RING);
                            int first = Math.min(n, RING - at);
                            System.arraycopy(buf, 0, ring, at, first);
                            if (first < n) System.arraycopy(buf, first, ring, 0, n - first);
                            len += n;
                            fetched += n;
                            if (!prebufDone && (len >= PREBUF
                                    || (size > 0 && base + len >= size))) {
                                prebufDone = true;
                                android.util.Log.i("tvplay", "cache prebuf ready len=" + len);
                            }
                            if (fetched / (8 * 1024 * 1024) != (fetched - n) / (8 * 1024 * 1024))
                                android.util.Log.i("tvplay", "cache dl base=" + base + " len=" + len
                                        + " fetched=" + fetched);
                            lock.notifyAll();
                        }
                    }
                } catch (Exception e) {
                    if (closed) return;
                    try { Thread.sleep(300); } catch (InterruptedException ignored) { }
                } finally {
                    if (c != null) c.disconnect();
                }
            }
        }
    }
}
