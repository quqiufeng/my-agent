# rangeserve — 带 Range 的只读 HTTP 文件服务

给 VLC 等播放器点播 NAS 上的大文件用；支持 `Range`（拖动/续播）与 HTTP/1.1 keep-alive。
也可用于托管 HLS 分片等静态流媒体目录。

```bash
ROOT=/path/to/media PORT=8099 python3 rangeserve.py
```

支持的 Range：`bytes=0-`、`bytes=100-200`、**后缀 `bytes=-65536`**（读 MKV 尾部 cues 必需）、
非法范围返回 `416`；`HEAD` 只回头。旧版本把后缀范围当成 `0-N`，会导致 MKV 起播/seek 异常。

systemd（极空间 Z2Pro 上已装为 `rangeserve.service`）：

```ini
[Service]
Environment=ROOT=/tmp/zfsv3/sata11/18072858035/data
Environment=PORT=8099
ExecStart=/usr/bin/python3 /opt/rangeserve/rangeserve.py
Restart=always
```

注意：`protocol_version = "HTTP/1.1"` 必须保留——HTTP/1.0 每次请求都断连，电视端会因小缓冲反复“buffer low”卡顿。

排查：如果 `systemctl status rangeserve` 显示 `activating (auto-restart)` + `Address already in use`，
说明有旧进程（常见是手工起的 `/tmp/rangeserve.py`）占着 8099；杀掉旧 PID 后 `systemctl restart rangeserve`，
再用 `curl -sI -r 0-1 http://192.168.1.53:8099/<file>` 确认响应是 `HTTP/1.1 206`。
