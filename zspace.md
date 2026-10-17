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

## 家庭网络拓扑（2026-10-18 实测）

```
光猫 192.168.1.1（中国电信智能网关 / LuCI；MAC a0:36:79:d5:35:e0）
  └─ 路由器（桥接/AP 模式，不做 NAT）
       ├─ 电脑 192.168.1.10/24（网线 enp34s0，网关直接是 192.168.1.1）
       ├─ 手机 vivo V2068A 192.168.1.99（WiFi；ssh 8022、adb 5555、CamStream 8080）
       ├─ 极空间 Z2Pro 192.168.1.53（网线 eth0；SSH 12200）
       └─ 科沃斯扫地机 192.168.1.98（WiFi wifi332；MAC ec:30:8e:20:7b:5e）
```

| 设备 | IP | 接入 | 备注 |
|---|---|---|---|
| 光猫（中国电信智能网关） | 192.168.1.1 | — | LuCI `/cgi-bin/luci`，MAC `a0:36:79:d5:35:e0` |
| 路由器（桥接/AP） | — | — | 不 NAT，PC 网关直接指向光猫 |
| 电脑（quqiufeng） | 192.168.1.10 | 网线 `enp34s0` | 跑 my-agent / Flutter 界面（四路视频+手机麦克风） |
| 手机 vivo V2068A | 192.168.1.99 | WiFi | Termux(8022)、无线 adb(5555)、CamStream 视频/音频(8080)、kiosk(VNC 5900) |
| 极空间 Z2Pro | 192.168.1.53 | 网线 `eth0` | SSH 12200，Docker 24，zfrp/DDNS 内网穿透 |
| 科沃斯扫地机 | 192.168.1.98 | WiFi `wifi332` | MAC `ec:30:8e:20:7b:5e`；`operator/tools/vacuum.sh` 控制 |
| 小机箱（客厅机） | 192.168.1.68 | 网线 `enp2s0` | i5-2400(4C)/11G/120G NVMe，Ubuntu 24.04（自定义 6.8 内核）；SSH 22、RDP 3389、免密 sudo；**无无线网卡**；MAC `00:e0:6b:25:23:20`；已配本机免密 SSH |
| Sony 电视 | 待定 | 待定 | 尚未开 ADB；计划做“拉流播放器 + 监控墙” |

- **只有一个子网 `192.168.1.0/24`**：电脑/手机/NAS/扫地机天然互通，**不存在“两个子网”问题**。
- 只有手机离开这个 WiFi（4G/别处）时才需要中转：NAS 的 `zfrp` 端口映射（按端口），或 Tailscale/WireGuard（整段互通，安卓需 VpnService App）。
- 排查方法（本机无 `ping`/`nmap`）：读 `/proc/net/arp`、SSDP M-SEARCH、按端口探测；`avahi-browse` 可用。
- 局域网还扫到若干未识别主机（如 .5/.23/.46/.52/.59 等），暂不列入。

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
