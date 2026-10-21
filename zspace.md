# 极空间 Z2Pro (ZSpace NAS) — 连接与探索

> 局域网 NAS。本机已配好免密 SSH。更新：2026-10-13（只读探索，未改任何配置）。

## 连接方式

```bash
# 推荐：用别名（已在 ~/.ssh/config）
ssh zspace '命令'          # 或 ssh nas
scp 文件 zspace:/路径/      # 传文件

# 直连（不依赖别名）
ssh -p 12200 18072858035@192.168.1.53
```

- **IP / 端口**：`192.168.1.53`，SSH `12200`（对外端口，内部转发到本机 `zbasic` 服务）
- **SSH 用户名**：`18072858035`（手机号）
- **免密**：本机 `~/.ssh/id_ed25519.pub` 已写入其 `~/.ssh/authorized_keys` ✅
- **提权**：`sudo -n <cmd>` 直接 root（用户 `18072858035` 在 sudo 组，**免密 sudo**）
- **密码**（备用/敏感）：`$$Wuyou272097579`
- **Web 管理**：`https://192-168-1-53.z2pro-ucgu.direct.zspace.link:5056/`（需登录）；本地 `:5055`/`:5056`

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
| SoC | **Rockchip RK3568**（4×Cortex-A55，aarch64），GPU=Mali-G52 |
| 系统 | **ZOS**（基于 **Debian 11 bullseye**），版本 `Z022_SERVICE V1.0.0220500` |
| 内核 | `5.10.110`（device-tree model: `Rockchip RK3568`）|
| 内存 | 3.6 GiB（+ 4×zram swap）|
| **显示** | **有 HDMI 输出**（`card0-HDMI-A-1`）；正在跑 **Xorg :0** + `xnasdesktop`(Xfce) + `player-qt` |
| **媒体** | 有 **VPU 硬解**（`/dev/mpp_service`）、2D 加速 `/dev/rga`、`dma_heap` → 能硬解/转码 |
| 温度 | soc ~51℃ / gpu ~48℃（`soc_thermal`/`gpu_thermal`）|
| LED | `power-led-*`、`hdd1/2-led-*`、`mmc0::` |
| 常用工具 | python3、git、gcc、make、ffmpeg、aria2c |
| Docker | **24.0.0**（data-root `/data_s002/data/udata/real/docker`，镜像源 `registry.zenithspace.net`）|
| 面板 | **1Panel**（`:18140`）+ `appstore` 应用市场 |

## 存储（详解）

| 挂载点 | 设备 | 类型 | 容量 |
|---|---|---|---|
| `/` | `mmcblk0p6` | ext4 | 14G |
| `/zspace` | `mmcblk0p8` | ext4 | 12G |
| `/zspace/applications/logs` | `mmcblk0p9` | ext4 | 1G |
| `/zspace/zsrp` | `md1`(raid1, sda3/sdb3) | ext4 | 20G |
| `/data_s001` | `bcache0` | **btrfs** | 3.6T |
| `/data_s002` | `bcache1` | **btrfs** | 3.6T |
| `/zspace/extdev/xPi32aDs` | `nvme0n1p1` | NTFS(fuseblk) | 238G |
| `/tmp/zfsv3` | `zfuse.zfsv3` (**FUSE**) | 自研 | 7.3T |
| swap | `md0`(3G raid1) + 4×`zram`(464M) | — | — |

- 每块 HDD 布局：`p1=md0(swap)`, `p3=md1(zsrp)`, `p2(8M bcache)+p4(3.6T)` → dm‑linear → **bcache+btrfs**。
- **`zfsv3` 不是真 ZFS**：是 ZSpace 自研 **FUSE 文件系统**（服务 `zspoolv3`，挂 `/tmp/zfsv3`）。另有 `rescuefs`、`zextfs`（外接盘）。
- SMART：sda **PASSED**；磁盘休眠 1800s。

## 网络 / 协议 / 端口

- **SSH**：对外 `12200`（`zbasic` 服务，支持任意用户 `adduser_z*`）；本地 `22`
- **SMB** 139/445 · **NFS** 111/2049（导出 `/nfs/`、`/tmp/zfsv3/share_fake/share`）· **WebDAV** · **FTP** · **AFP**(Mac) · **SFTP** · **DLNA** minidlna:8200
- **RTSP 代理** `:554`→`rtsp8554`（把摄像头/视频转 RTSP 出去）
- **Web 网关**：openresty（5055/5056 + 多个 127.0.0.1 端口 2999/8020/8111/20123…）
- 本地微服务端口（`127.0.0.1`）：`zds`5577、`downloader`8001、`storage-pool`8003、`zspoolv3`8004、`transcode`8010、`upgrader`8012、`leds`8022、`file_search`8023、`media-converter`8024、`netdiskv2`8027、`zmusic`8028、`zreader`8029、`baseset`8038… ；`zrps-worker`5050、`xunlei`5051/5052、`zbasic`12200(对外)

## 家庭网络拓扑（2026-10-21 实测）

```
光猫 192.168.1.1（中国电信智能网关；MAC a0:36:79:d5:35:e0）
  └─ AP/路由 192.168.1.52（H3C；MAC 00:be:d5:22:7b:3c；桥接，不 NAT）
       ├─ 主电脑 quqiufeng 192.168.1.10/24（网线 enp34s0）
       ├─ 小机箱（客厅）192.168.1.105/24（USB WiFi MT7612U，SSID wifi332；MAC 8c:3d:16:62:3c:1e）
       │    ├─ HDMI3 → Sony 电视（BRAVIA，画面）
       │    ├─ 3.5mm 绿色孔 → 小音响（默认音频输出）
       │    └─ USB → Comica EJoy Uni 麦克风（默认输入）
       ├─ 极空间 Z2Pro 192.168.1.53（网线 eth0；SSH 12200）
       └─ 其他在线设备：.5/.8/.17/.23/.46/.47/.48（未识别）
```

| 设备 | IP | 接入 | 备注 |
|---|---|---|---|
| 光猫（中国电信智能网关） | 192.168.1.1 | — | LuCI `/cgi-bin/luci`，MAC `a0:36:79:d5:35:e0` |
| AP/路由（H3C，桥接） | 192.168.1.52 | — | 不 NAT；MAC `00:be:d5:22:7b:3c`，HTTP 管理页在线 |
| 主电脑（quqiufeng） | 192.168.1.10 | 网线 `enp34s0` | 跑 my-agent / 界面；网关直接是 `192.168.1.1` |
| 小机箱（客厅机） | 192.168.1.105 | USB WiFi `wifi332`；有线 `enp2s0` 备用 | i5-2400/11G/115G，Ubuntu 24.04.5 + Lubuntu；SSH 22、免密；HDMI 画面到 Sony 电视；3.5mm 小音响；Comica USB 麦克风；MAC `8c:3d:16:62:3c:1e` |
| 极空间 Z2Pro | 192.168.1.53 | 网线 `eth0` | SSH 12200，Docker，WebDAV 5005，zfrp/DDNS 内网穿透 |
| Sony 电视（BRAVIA） | 待确认 | HDMI3 ← 小机箱 | 独立设备/显示端；小机箱接 HDMI3；电视音频未使用，声音固定走小音响；ADB 5555 当前不可达，需在电视上开 ADB 调试并确认 IP |
| 其他在线未识别 | .5/.8/.17/.23/.46/.47/.48 | 局域网 | 暂不归类 |

- **只有一个子网 `192.168.1.0/24`**：主电脑、小机箱、NAS、AP 管理口天然互通。
- 小机箱当前无线在线（`.105`），原客厅有线地址 `.68` 仅作备用，当前未插。
- 小机箱音频：视频画面走 HDMI3 到 Sony 电视；声音固定 3.5mm 绿色孔小音响；麦克风走 Comica USB。
- Sony ADB 可用时，`input keyevent 245` 可切 HDMI3（HDMI1–4 对应 243–246）；当前 5555 不可达。
- 客厅摄像头为 EZVIZ 云服务，不作为局域网内固定 IP 设备列出。
- 排查方法（本机无 `ping`/`nmap`）：读 `/proc/net/arp`、SSDP M-SEARCH、按端口探测；`avahi-browse` 可用。

## 容器 / 应用生态（极丰富）

- **Docker + Portainer + appstore**（`/var/appstore/pkg`、`/data_s00*/appstore/pkg`）
- **下载**：qbittorrent、transmission、aria2、**迅雷**(xunlei)
- **同步/网盘**：**syncthing**、minio；云盘挂载 **adrive(阿里云盘)**、**kuake(夸克)**；`zfrp` **内网穿透**
- **媒体**：video + `transcode`/`media-converter`（VPU 硬解）、music/`zmusic`、`zreader`、`player-qt`
- **相册**：`zalbumv2` + **manticore** 全文/语义搜索
- **摄像头 NVR**：`znvr`（可接 IP 摄像头）
- **数据库**：mysql、pgsql、redis；**php**、**nginx**、**webdav**、ftp/sftp/afp/samba/nfs
- **办公/其他**：onlyoffice、`zjdxb`(AI?)、`wxrobot`、family、zclasses、comics、audioBooks、bookLib、zvirusscan、cloudBackUp/zbakv2(备份)、ddns、zfirewall、bluetooth

## 管理与 OTA

- `/zspace/shell/`：整套管理脚本（`install/factory_test/flasher/migrate/create_user/mysql_backup/check_*/ipv6_*/led_power_green` …）
- `/zspace/package.json`：**OTA 应用清单**（各服务名 + 版本 + git 分支/commit），`upgrader` 服务执行升级；`monit` 监控进程
- 配置：`/zspace/system/`（version、setting、account.master、db、fileshare_service…）

## 用户

| 用户 | uid | 说明 |
|---|---|---|
| `linaro` | 1000 | 系统默认（nologin）|
| `nut` | 1001 | UPS 服务 |
| `18072858035` | 1004 | **我的账号**（/bin/bash，SSH 用它）|
| `13456906403` | 1005 | 另一账号（nologin）|
| `guest` | 1006 | 访客 |

## 结论 / 可玩方向

**总之：这是一台 RK3568 + HDMI + VPU + Docker + X 桌面的「小服务器」，远强于 Kindle。**

1. **Docker 部署任意服务**：Jellyfin/Emby（有 VPU 硬解 + HDMI，直接接电视）、Gitea、数据库、Alist、Home Assistant…
2. **HDMI 接电视** → HTPC/桌面/播放器（`xnasdesktop`/`player-qt` 已在跑）；
3. 把 IP 摄像头接进 **NVR(znvr)**；
4. 当 **PT 下载机 + 云盘同步 + 内网穿透(zfrp)**；
5. 深挖 **zfsv3/zspoolv3** 自研存储、OTA、能否装第三方 App；
6. 有 **root（sudo 免密）**，可自由折腾。

> ⚠️ 密码/敏感信息勿外泄。以上为**只读探索**结论，未修改任何配置。
