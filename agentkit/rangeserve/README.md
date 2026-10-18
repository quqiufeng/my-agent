# rangeserve — 带 Range 的只读 HTTP 文件服务

给电视播放器（tvplay/VLC）点播 NAS 上的大文件用；支持 `Range`（拖动/续播）与 HTTP/1.1 keep-alive。

```bash
ROOT=/path/to/media PORT=8099 python3 rangeserve.py
```

systemd（极空间 Z2Pro 上已装为 `rangeserve.service`）：

```ini
[Service]
Environment=ROOT=/tmp/zfsv3/sata11/18072858035/data
Environment=PORT=8099
ExecStart=/usr/bin/python3 /opt/rangeserve/rangeserve.py
Restart=always
```

注意：`protocol_version = "HTTP/1.1"` 必须保留——HTTP/1.0 每次请求都断连，电视端会因小缓冲反复“buffer low”卡顿。
