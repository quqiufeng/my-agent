# 极空间 Z2Pro (ZSpace NAS) 连接与速查

> 局域网 NAS，本机已配置好免密 SSH。更新：2026-10-13。

## 连接方式

```bash
# 推荐：用别名（已在 ~/.ssh/config）
ssh zspace '命令'          # 或 ssh nas
scp 文件 zspace:/路径/      # 传文件

# 直连（不依赖别名）
ssh -p 12200 18072858035@192.168.1.53
```

- **IP / 端口**：`192.168.1.53`，SSH `12200`（对外端口，内部转发到本机 22）
- **SSH 用户名**：`18072858035`（手机号）
- **免密**：已把本机 `~/.ssh/id_ed25519.pub` 写入其 `~/.ssh/authorized_keys` ✅
- **提权**：`sudo -n <cmd>` 直接 root（该用户在 sudo 组，**免密 sudo**）
- **密码**（备用/敏感）：`$$Wuyou272097579`
- **Web 管理**：`https://192-168-1-53.z2pro-ucgu.direct.zspace.link:5056/`（需登录）

### `~/.ssh/config` 片段
```
Host zspace nas
  HostName 192.168.1.53
  Port 12200
  User 18072858035
  IdentityFile ~/.ssh/id_ed25519
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
```

## 硬件 / 系统
| 项 | 值 |
|---|---|
| 型号 / hostname | 极空间 **Z2Pro** / `Z2Pro-UCGU` |
| SoC | **Rockchip RK3568**（4×Cortex-A55，aarch64）|
| 系统 | **ZOS**（基于 **Debian 11 bullseye**）|
| 内核 | `5.10.110` |
| 内存 | 3.6 GiB |
| Docker | **24.0.0**（containerd 在跑）|
| 常用工具 | python3、git、gcc、make、ffmpeg、aria2c |

## 存储
| 挂载点 | 设备 | 容量 |
|---|---|---|
| `/` | `/dev/root` | 14G (48%用) |
| `/zspace` | `/dev/mmcblk0p8` | 12G |
| `/zspace/zsrp` | `/dev/md1` | 20G |
| `/data_s001` | `/dev/bcache0` | 3.7T |
| `/data_s002` | `/dev/bcache1` | 3.7T |
| `/zspace/extdev/xPi32aDs` | `/dev/nvme0n1p1` | 239G |
| **ZFS 池 `zfsv3`** | (7.3T) | → `/tmp/zfsv3`；NFS 导出 `/tmp/zfsv3/share_fake/share` |

## 网络服务 / 端口（部分）
- **SSH**：12200
- **SMB**：139/445（共享：`共享文件`，匿名可列）
- **NFS**：111(portmap) / 2049
- **Web 网关**：openresty 监听 5055 / 5056 等；`80/8080/8020/8111/…`(127.0.0.1)
- **1Panel**（`1panel-agent/core.service`）
- 应用：`minidlna`(8200 DLNA)、迅雷(`xunlei-pan-cli` 5051/5052)、`transcode`(8010)、`znvr`(摄像头NVR 8554)、`zalbumv2`(相册)、`zds` 等
- ZOS 自带 App：影视/相册/Office/音乐/有声书/摄像头/下载/微信机器人…

## 备注
- 对外只开放：SSH(12200)、SMB(139/445)、NFS(111/2049)、Web(5055/5056)。
- 有 **root（sudo 免密）**，可自由部署 Docker 服务 / 改配置。
- ⚠️ 密码等敏感信息，勿外泄。
