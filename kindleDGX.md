# Kindle DX Graphite (DXG) 折腾记录

> 汇总整理「把 Kindle DXG 当电子墨水副屏 / 可编程小主机」的全部探索。日期：2026-10-13。

---

## 0. 一句话结论

DXG 是一台**已越狱的 ARM/Linux 小机器**（kernel 2.6.22 + glibc 2.5，127MB 内存）。通过 **usbnet(USB 网卡) + SSH** 拿到 root，可以：
- 当**电子墨水副屏/仪表盘**（`eips` / `kindle_screen`）；
- 换字体（**仓耳今楷**，已生效）；
- 跑 **LuaJIT 2.1**（自己交叉编译的 musl 静态版，JIT 在 ARMv6 上生效）；
- 音频/TTS、注入按键、读 MOBI/PDF/EPUB。

**限制**：没有 WiFi（内核不支持）、不支持 AZW3/KF8、内存极小、跑不了现代 glibc 二进制。

---

## 1. 硬件与系统

| 项 | 值 |
|---|---|
| 机型 | Kindle DX Graphite（serial `B009...`；platform `Mario`，与 K3 同平台）|
| CPU | ARMv6（ARM1136，part `0xb36`），带 **VFP**（无 NEON），BogoMIPS ~1594 |
| 内核 | `Linux 2.6.22.19-lab126` (`#3 PREEMPT`, 2012-01) |
| libc | **glibc 2.5**（`/lib/libc-2.5.so`）|
| 用户态 | `busybox 1.7.2`（`/bin/busybox`, setuid），dropbear 0.52 |
| 内存 | 127MB（常只剩 4~10MB 空闲）|
| 屏幕 | e-ink 1200×824 横屏；framebuffer `/dev/fb0` = **824×1200，4bpp，stride 412** |
| 固件 | `Kindle 3.2.1` |
| 存储 | rootfs `/dev/mmcblk0p1` (398M, **ro**)；`/var/local` = `mmcblk0p2` (23M, rw)；`/mnt/us` = `mmcblk0p4` (3.3G, FAT via **fsp FUSE**) |
| 输入 | `fiveway`(event1)、`mxckpd`(event0)、加速度计 `mma7660F`、`uinput` |
| 音频 | ALSA（`mxc_alsa_pmic`/`snd_pcm`）；`aplay/arecord/amixer/say/ttsd/gst-launch` |
| 网络芯片 | 有 **Atheros AR6002** 固件（`/opt/ar6k`）但**内核未编 WLAN → 无 WiFi** |

常用命令：`/usr/sbin/eips`（画屏）、`/usr/sbin/lipc-*`（Kindle IPC）、`system_state`、`gasgauge-info`（电量）、`mntroot rw|ro`（切 rootfs 读写）。

---

## 2. 越狱 / SSH 访问

- 系统已越狱（`/etc/rc5.d/S64jailbreak`），装了 `linkfonts`、`linkss`、`usbnet`、`kindlepdfviewer`、`launchpad` 等。
- **usbnet**：`/mnt/us/usbnet/`（`auto` 文件触发；`etc/config` 里 `HOST_IP=192.168.2.1`、`KINDLE_IP=192.168.2.2`、`K3_WIFI=false`）。
  - 在 `g_file_storage`(U盘) 与 `g_ether`(网卡) 间切换模块。
  - **只在开机时**初始化 usb0 + dropbear（拔插线不重跑）。
- SSH 免密：dropbear 用 `-n`（空密码），任何密码都放行。

### 主机侧 SSH 配置（`~/.ssh/config`）
```
Host kindle
  HostName 192.168.2.2
  User root
  KexAlgorithms +diffie-hellman-group1-sha1
  HostKeyAlgorithms +ssh-rsa
  PubkeyAcceptedAlgorithms +ssh-rsa
  Ciphers +aes128-cbc,3des-cbc,aes256-cbc
  PubkeyAuthentication no
  PreferredAuthentications password
  NumberOfPasswordPrompts 1
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

### 免弹框包装（避免图形密码框反复弹出）
- `~/.ssh/kindle_askpass.sh`：`echo ""`（喂空密码）
- `~/.local/bin/kx`：`SSH_ASKPASS=... SSH_ASKPASS_REQUIRE=force setsid -w "$@"`
- 用法：`kx ssh kindle '...'`、`kx scp -O file kindle:/mnt/us/`

### 主机 USB 网卡自动配置
- 网卡名会变（`usb0` ↔ `enxee4900000000`）。
- `/etc/udev/rules.d/70-kindle-usbnet.rules` + `/usr/local/bin/kindle-usbnet-up.sh`：按 MAC `ee:49:00:00:00:00` 自动 `ip link up` + `ip addr replace 192.168.2.1/24`。
- **Clash 会拦 192.168.2.x**：需 `ip rule add to 192.168.2.0/24 lookup main priority 100`。

---

## 3. 显示（电子墨水副屏）

- `eips` 用法：`eips [-c|-f] [-g file | x y "text"]`；`-g` 画图、`-f` 全刷、`-c` 清屏。**必须用全路径 `/usr/sbin/eips`**。
- 图片规格：**1200×824** 横版 PNG（eips 自动旋转到 824×1200 的 fb）。灰度用 `convert ... -colorspace Gray -resize 1200x824! -colors 16 -type Grayscale`。

### `kindle_screen` 工具（`~/.local/bin/kindle_screen`）
- `kindle_screen once` — 截主机屏幕投一次
- `kindle_screen loop [秒]` — 循环刷新（副屏）
- `kindle_screen img <图>` — 推本地图片
- `kindle_screen text "文字" [x y]` / `clear`
- 环境变量 `KS_GEOM=WxH+X+Y` 指定区域。

### 读 framebuffer 抓屏（主机侧解码）
```
dd if=/dev/fb0 ... ; # 824×1200, 4bpp, stride 412 → 每字节两个像素(高低半字节)
```

### ⚠️ 大坑：**开机插着 USB 会进 `USB Drive Mode`**
- 现象：framework 把用户分区当移动盘交出（`lipc-get-prop com.lab126.volumd driveModeState` = 1，`userstoreIsAvailable` = 0），屏幕显示 "USB Drive Mode"（一大片白）→ 一拔线就白屏/空白。
- `lipc-send-event usbUnconfigured`、`useUsbForNetwork=1` 都**没能**退出；`orientation` 属性是**只读**（`com.lab126.system`）。
- **恢复**：拔掉 USB + 整机重启（`/sbin/reboot`）；开机时**别插 USB** 就不会进 Drive Mode。
- usbnet 与「开机不插线」有矛盾 → 这是 USB 远程方案的固有代价。

---

## 4. 字体（已换成仓耳今楷）

- Hack：`linkfonts v4.9.N`，把 `/mnt/us/linkfonts/fonts` **bind-mount** 到 `/usr/java/lib/fonts`。
  - 系统按固定名读字体：`Serif_{Regular,Bold,Italic,BoldItalic}.ttf`、`Sans_*`、`Mono_*`、`CJK.ttf`、`CJK_Bold.ttf`、`I18N.ttf`。
  - 备份在 `/mnt/us/linkfonts/backups/`。
- **框架字体引擎 (cvm) 很挑**：换个「它不喜欢」的字体 → 日志 `Could not load freetype font ".../Serif_Regular.ttf"` → 界面空白/花屏。

### ✅ 成功配方（关键两步）
1. **启用 FreeType 覆盖**：`touch /mnt/us/linkfonts/autohint`（或 `light`/`bci`）→ 会把 `/mnt/us/linkfonts/lib/{autohint}/libfreetype.so` bind 到 `/usr/lib/libfreetype.so.6.3.20`。
2. **改字体后必须整机重启，且拔掉 USB**（framework restart 不够）。

### 仓耳今楷02 处理要点
- 原字体：TTF，upem 1000，29061 字形，**带竖排表 VORG/vhea/vmtx/BASE** → 框架不认。
- 用 `pyftsubset` **子集化**（GB2312 全部字 + ASCII + 标点，约 7900 字）+ `--drop-tables+=VORG,vhea,vmtx,BASE` → ~3.9MB。
- 10 个名字都用仓耳今楷（W04 作 Regular、W05 作 Bold）。
- 参考：Amazon 原装 CJK `MHeiM18030_E.ttf`（glyf、upem 256、无竖排表）→ 结构对照。

---

## 5. 网络 / WiFi

- **WiFi 不可用**（技术上可绕过一点但最终失败）：
  - 运行内核 `2.6.22.19-lab126` 的 `config`：`CONFIG_WLAN_80211 is not set`（没编无线栈）。
  - 唯一的 `ar6000.ko` 是给**另一个内核** `2.6.26-rt-lab126` 的（vermagic 不匹配）。
  - 尝试：剥掉 `.ko` 的 `__versions` 段（`llvm-objcopy-18 --remove-section=__versions`）+ 改 `.modinfo` 的 vermagic 为 `2.6.22.19-lab126 preempt mod_unload ARMv6` → 仍失败：内核缺平台符号 `gpio_wifi_power_enable / sdhci_sdio_stop_gating / mxc_kernel_uptime / alloc_etherdev_mq_ar6000 ...`。
  - 结论：**这台 DXG 固件内核层面就不支持 WiFi**，只能重编内核。
- 有 3G 模块（`/dev/tts/USB0` 等）但无服务。
- 远程只能走 **USB(usbnet)**。

---

## 6. 电子书格式

- **不支持 AZW3/KF8**（KF8 从 K3 的 FW 3.4 起才有；DXG 是 3.2.1）。MobileRead `t=345335` 原话：*"No KF8/AZW3. No publisher fonts."*
- 支持：**MOBI**（老式）、**PDF**、**EPUB**（用机器里的 `kindlepdfviewer`）。
- AZW3 → MOBI **非无损**（丢内嵌字体/复杂排版/多栏/SVG；文字图片基本保留）。纯文字小说几乎无感。
- 更保真：转 **ePub** 用 kindlepdfviewer；或换支持 KF8 的机型。
- 已清空 `/mnt/us/documents`（释放 ~460MB，`/mnt/us` 现用 ~530MB）。

---

## 7. 开发：LuaJIT / 交叉编译

### LuaJIT
- 自带：`kindlepdfviewer` 打包了 **LuaJIT 2.0.0**（解释器 `/mnt/us/kindlepdfviewer/kpdfview`，库 `.../libs/libluajit-5.1.so.2`）。
- **已装最新 LuaJIT 2.1**：`/mnt/us/luajit`（自编译 musl 静态版）。
  ```
  /mnt/us/luajit -e "print(jit.version, jit.arch, jit.status())"
  # LuaJIT 2.1.1788856981  arm  true ARMv6 VFPv2 fold cse dce ...
  ```

### ⚠️ 交叉编译的关键坑
- **现代 glibc 静态二进制在老内核 2.6.22 上段错误**（连 hello world 都挂）。
- **必须用 musl 静态**才能跑。
- 工具链：`arm-linux-musleabi-cross`（musl.cc）；`HOST_CC="gcc -m32"`（需 `gcc-multilib` + `libc6-dev-i386` + `linux-libc-dev:i386`）。
- 构建 LuaJIT 示例：
  ```bash
  make -j4 HOST_CC="gcc -m32" \
    CROSS=$PWD/arm-linux-musleabi-cross/bin/arm-linux-musleabi- \
    TARGET_SYS=Linux \
    TARGET_FLAGS="-march=armv6 -mfloat-abi=softfp -mfpu=vfp -marm" \
    TARGET_LDFLAGS="-static"
  ```
- `arm-linux-gnueabi-*`（armel/glibc）只用于产 ELF 分析，别用它静态链接 glibc 跑。

---

## 8. 可用工具/引擎（Kindle 自带）

`/usr/bin`：`curl wget openssl sqlite3 strace gdb htop top rsync gst-launch dbus-* lipc-* tsl evtest recEvent unzip` 等。
`/usr/sbin`：`eips eiputs dropbearmulti iptables mntroot mntus otaup pppd ttsd wifid` 等。
Java 框架：`cvm`（`/usr/java/bin/cvm`），阅读器 `libTopaz`。

---

## 9. 已产出的实用脚本 / 命令

| 位置 | 作用 |
|---|---|
| `~/.local/bin/kx` | 免密码弹框 ssh/scp 包装 |
| `~/.local/bin/kindle_screen` | 主机→Kindle 副屏（once/loop/img/text/clear）|
| `~/.ssh/kindle_askpass.sh` | 空密码 askpass |
| `/usr/local/bin/kindle-usbnet-up.sh` + `/etc/udev/rules.d/70-kindle-usbnet.rules` | 主机 USB 网卡自动配 IP |
| `/mnt/us/luajit` (Kindle) | LuaJIT 2.1（musl 静态，ARMv6 JIT）|
| `/mnt/us/linkfonts/autohint` (Kindle) | 启用 FreeType 覆盖（字体生效关键）|

### Kindle 端状态速查
```bash
kx ssh kindle 'uptime; lipc-get-prop com.lab126.volumd driveModeState; \
  ls -l /mnt/us/linkfonts/fonts/Serif_Regular.ttf; ls /mnt/us/luajit'
```

---

## 10. 关键经验（踩坑清单）

1. **带 USB 开机 → USB Drive Mode → 空白**：改硬件相关操作后要**拔线重启**。
2. **改字体**：必须「开 FT 覆盖 + 拔线整机重启」；cvm 只接受它认的 TTF（去竖排表 + autohint 覆盖）。
3. **FB 是 824×1200 / 4bpp**，eips 收 1200×824 横图。
4. **老 busybox grep 不支持 `-E`**；`rm` 不支持 `-v`；`insmod/modprobe` 不在 PATH（在 `/sbin/*.26`）。
5. **现代 glibc 静态程序跑不了**（段错误）→ 用 **musl 静态**。
6. **无 WiFi**（内核没编 WLAN，缺平台符号）；远程只能 USB。
7. **AZW3 不支持**；MOBI/PDF/EPUB（kindlepdfviewer）可用。
8. 老内核 + 老工具链：`insmod -f` 过不了 modversions/vermagic，需 `objcopy` 剥段 + 改 `.modinfo`。

---

## 11. GitHub 今日热门 → Kindle（示例应用）

用 my-agent 现成的数据源出图，再推给 Kindle：
```bash
# 1) 取数据（my-agent 的 agentkit）
luajit -e 'package.path="/opt/my-agent/?.lua;/opt/my-agent/?/init.lua;"..package.path
  local ak=require("agentkit"); local gh=ak.app("github")
  for _,r in ipairs(gh.trending({since="daily",limit=8})) do
    print(r.repo.."\t"..r.stars_today.."\t"..r.lang.."\t"..r.desc) end' > /tmp/gh.tsv
# 2) 生成 1200×824 横版 Kami HTML（复用 operator/report/kami.css）→ Chrome headless 截图
# 3) 转灰度 → scp → eips -f -g
```
（也可直接用 `kindle_screen img <图>` 推送。）

---

## 12. 作为嵌入式测试平台

**定位**：一台**真实的老嵌入式 ARM/Linux**（ARMv6 + glibc 2.5 + kernel 2.6.22，127MB RAM），既是「交叉编译/兼容性靶机」，又是「可编程的墨水屏显示 + 交互终端」。

**适合用来测**：
- **交叉编译产物验证**：musl 静态 / glibc 兼容性（本机就是「现代 glibc 静态会段错误」的现成反例）。
- **脚本运行时**：LuaJIT 2.1（ARMv6 JIT 生效）跑自动化脚本/用例。
- **显示渲染**：framebuffer / `eips` 出图（1200×824）。
- **输入注入**：`uinput` 模拟按键/五向键，做 UI 自动化。
- **外设**：加速度计（mma7660F）、ALSA 音频输出（aplay/TTS）。
- **长稳/低功耗**：连着 USB 长跑，SSH 观察。

**当 CI/测试显示终端**：把测试结果、通过率、仪表盘、摄像头抓拍等绘成 1200×824 图 → `kindle_screen img` 投到墨水屏（常驻 `kindle_screen loop`）。

**部署方式**：
```bash
# 主机交叉编译(musl 静态) → 推 → 跑
kx scp -O ./test_bin kindle:/mnt/us/
kx ssh kindle 'chmod +x /mnt/us/test_bin && /mnt/us/test_bin'
# Lua 用例
kx scp -O ./case.lua kindle:/mnt/us/ && kx ssh kindle '/mnt/us/luajit /mnt/us/case.lua'
```
（可封装成 `kindle_deploy.sh <二进制> [参数]`：编译→推送→执行→回显，结果同时投屏到墨水屏。）

**限制**：无 WiFi（只能 USB）、RAM ≤127MB、内核 2.6.22、不支持 AZW3/KF8。

---

## 13. musl 嵌入式底座（与系统共存）

**目的**：给 DXG 一套「较新 libc（**musl**）」的独立用户态，用 **chroot** 跑，与系统（`glibc 2.5`）**分进程共存**——这就是这台机唯一可行的「新 libc 底座」。
（为什么不是新 glibc：内核 2.6.22 太老，新 glibc 起不来；详见 §关于 glibc 升级的结论。）

### 组成（都在设备 `/mnt/us/`）
- `/mnt/us/newroot.ext3` — **64MB ext3 镜像**（loop 挂载），内含：
  - `/bin/busybox`（**musl 静态**，403 个 applet 软链）
  - `/lib/libc.so` + `/lib/ld-musl-arm.so.1`（musl 动态库，供动态程序）
  - `/etc/{passwd,group,resolv.conf,hostname}`
- `/mnt/us/nr` — 挂载点
- `/mnt/us/nr.sh` — 一键进入脚本（挂载 ext3+proc+sys+dev → chroot）

### 用法
```bash
# 进底座 shell
kx ssh kindle 'sh /mnt/us/nr.sh'
# 直接在底座里执行命令
kx ssh kindle 'sh /mnt/us/nr.sh /bin/sh -c "uname -a; ls /; busybox | head -1"'
# 把主机程序放进底座并运行
kx scp -O ./app kindle:/mnt/us/ ; kx ssh kindle 'cp /mnt/us/app /mnt/us/nr/root/; sh /mnt/us/nr.sh /root/app'
```

### 工具链与编译
- 工具链：`~/opt/arm-linux-musleabi-cross`（musl.cc 的 `arm-linux-musleabi`）
- 编译参数：`-march=armv6 -mfloat-abi=softfp -mfpu=vfp`（静态或动态皆可）
- 模板工程：`~/kindle-emb/`（`make` / `make run`）

### 踩过的关键坑
1. **内核只支持 `ext3`**（无 ext2/ext4）→ 镜像必须做成 **ext3**（`mke2fs -t ext3`）。
2. **FAT(`/mnt/us`) 不支持软链接** → busybox applet / ld 软链会丢；所以用 **ext3 镜像 + loop 挂载** 承载 rootfs。
3. **现代 glibc 静态在老内核段错误** → 必须 musl（见 §7）。
4. `busybox --install -s` 要在**可写且支持软链**的 fs 上跑（ext3 镜像里跑即可）。

### 重建/扩容底座（主机侧）
```bash
ROOT=/tmp/opencode/newroot          # 预置好 busybox + musl 的目录
truncate -s 64M newroot.ext3
mke2fs -q -F -t ext3 newroot.ext3
sudo mount -o loop newroot.ext3 /mnt && sudo cp -a $ROOT/. /mnt && sudo umount /mnt
kx scp -O newroot.ext3 kindle:/mnt/us/
kx ssh kindle 'chroot /mnt/us/nr /bin/busybox --install -s /bin'   # 首次建 applet 软链
```

---

## 14. 自绘 GUI：LVGL + LuaJIT + agent 控制通道

**结论**：Flutter 在这台上不可行（无 GPU/GL/NEON）；自绘 GUI 走 **LVGL(C) 直接画 e-ink**。

### 架构（全部自己实现）
```
agent(my-agent) ──写 Lua 命令──▶ FIFO /tmp/ui.cmd
                                      │
        lvgui(C, musl 静态) = LVGL 8.3 + 内嵌 LuaJIT 2.1 + 控制循环
            │ 渲染(LVGL)                │ 执行 Lua(ui.* API)
            ▼                           ▼
         写 /dev/fb0(824x1200,4bpp)   事件追加 /mnt/us/ui/events
            │
         触发刷新 /proc/eink_fb/update_display
输入: 五向键 /dev/input/event1 → LVGL keypad
```

### 产物位置（设备）
- `/mnt/us/lvgui` — 单体可执行（LVGL+LuaJIT）
- `/mnt/us/ui/init.lua` — 启动脚本（定义初始界面）
- `/mnt/us/ui/{start.sh,stop.sh}` — 启停（暂停/恢复 cvm）
- FIFO `/tmp/ui.cmd`（**必须放 tmpfs**，FAT 不支持 FIFO）
- 事件 `/mnt/us/ui/events`

### Lua API
`ui.clear() title(s) label(s[,size]) text(x,y,s[,size]) set(obj,s) pos(obj,x,y) size(obj,w,h) align(obj,ui.ALIGN_CENTER,dx,dy) color(obj,hex) log(s) button(s[,cb])`
（`ui.ALIGN_*` 常量由 C 端注入。）

### e-ink 刷新（血泪结论，务必照做）
- **不要直写 `/dev/fb0` + 写 `/proc/eink_fb/update_display` 刷新**：会卡黑屏/花屏，只能重启复位。
- **唯一稳的方式 = `eips`**：`eips -f -g <图>`（系统自带、已验证）。
- **方向**：停掉 cvm 后 eink 方向会复位成竖屏 → 显示前先设横屏：
  `echo 14 2 > /proc/eink_fb/update_display`（`14`=方向命令，值为 `0/1/2/3`＝竖/竖倒/横/横倒）。
  ⇒ 已修进 `kindle_screen`（每次显示前自动设横屏）。
- **图片格式**：`eips` 认 **PNG**（和 convert 的 32bit BMP）；**自写的 8bit/经典头 BMP 它读不出**（画成白）→ app 里就**自己写 PNG**（存储式 deflate + CRC32，见 `lvgui.c`）。
- `update_display` 命令表：局部=`1`、整屏=`2`、方向=`14 <n>`、which+fx=`18 <2快 3慢>`；**整屏刷新不能高频发**。
- 排查坑：出问题后 `/dev/fb0` 的**读**会不可靠（面板正常但读出是花）→ 用 **USB 摄像头拍屏**验证（见 §15）。

### 编译（主机侧）
```bash
CC=~/opt/arm-linux-musleabi-cross/bin/arm-linux-musleabi-gcc
$CC -O2 -march=armv6 -mfloat-abi=softfp -mfpu=vfp -marm -DLV_CONF_INCLUDE_SIMPLE \
    -I lvgl -I lvgl/src -I lvport -I luajit/src \
    $(find lvgl/src -name '*.c') lvgui.c luajit/src/libluajit.a -o lvgui -static -lm
```

### 启停
```bash
# 起（暂停 Amazon 框架）
kx ssh kindle 'killall -STOP cvm; /sbin/start-stop-daemon -S -b -x /mnt/us/lvgui'
# 停（恢复框架）
kx ssh kindle 'pkill -f /mnt/us/lvgui; killall -CONT cvm'
# agent 推命令
kx ssh kindle 'printf "ui.title(\"Hello\")\n" > /tmp/ui.cmd'
```

---

## 15. 用 USB 摄像头拍屏验证 Kindle

Kindle 的 `/dev/fb0` 读在出问题后会不可靠，用桌面上的 **USB 摄像头**直接拍屏最准：

```bash
# 摄像头常被 myagent_ui 占用，先释放
pkill -f myagent_ui
# 抓一帧
ffmpeg -f v4l2 -input_format mjpeg -i /dev/video0 -frames:v 1 -update 1 -y /tmp/opencode/now.jpg
```
（`/dev/video1` 是同设备元数据节点，不支持抓流。）

**横屏显示图片**（停框架/显示图，方向正）：
```bash
kx ssh kindle 'killall -STOP cvm; echo 14 2 > /proc/eink_fb/update_display; /usr/sbin/eips -f -g /mnt/us/gh.png'
```
或直接用更新后的 `kindle_screen img <图>`（已内置设横屏）。

---

## 16. 自研电子书阅读器（书架 + 阅读）

**在 DXG 上完全自实现的电子书 UI**（LVGL + LuaJIT + FreeType），agent 可脚本驱动。

### 解析（复用 `/opt/my_db/tools/import_book`）
```bash
# 主机上把电子书(epub/mobi/azw/azw3/pdf)解析成逐页 Markdown（无需 GPU）
cd /opt/my_db
LD_LIBRARY_PATH=/opt/my_db ./tools/import_book /tmp/cache ~/book.mobi /books/书名 /opt/books --skip-vectors
# → /opt/books/书名/chapters/NN-章名/page_XXXX.md
# 再拼成纯文本 → /mnt/us/ui/books/<书名>.txt 推到 Kindle
```

### 渲染与交互
- 字体：`/mnt/us/ui/font.ttf`（CJK，FreeType 运行时加载）。**字号=真实像素**，按需加载并缓存
  （`ui.font(px)` / `ui.setfont`），三档 小22 / 中26 / 大34。
- 两屏（Lua）：**书架** + **阅读器**。正文用 `ui.text` 单个 label 装整页；
  分页用 `ui.measure` 实测字宽/行高来算每行字数与行数（**切字号必须重排**）。
- 按键：C `key_read` 读 event0/event1 → 主循环优先回调 `on_code(rawcode)`；无 `on_code` 才回退 `on_key(name)`。
  实机扫描码：Home 98 · Back 91 · Menu 139 · 上一页 109 · 下一页 124；五向 上122 下123 中92 左105 右106。
- 键默认被内核锁住：需 `echo unlock > /proc/keypad; echo unlock > /proc/fiveway`（init.lua 已做），无需额外 keyd。
- 显示：抗锯齿边缘经 gamma 1.8 压暗，墨水屏上文字更实；状态栏贴近底边。
- **刷新策略**：默认局部刷新（`eips -g`，翻页不闪）；切屏/换字号/锁屏/每 12 次局部自动全刷（`-f`）消残影。
- **游戏**：内置贪吃蛇（`boot/lua/snake.lua`，菜单进入）。为此补了 `on_tick(100ms)`、任意按键透传、
  `ui.flushrect()` 矩形局部推送；实测全屏刷新 ~680ms（png 86 + lvgl 248 + eips 349），
  局部推送后约 2.7 步/秒。字体缺 `█`/全角空格（只有 10px），用 `■ □ ● ◆ ★` 才是 20px 全角。
- 开发指南：`/opt/my-agent/agentkit/kindle/boot/lua/README.md`
- **顶部 lock 开关有效**：拨动时驱动锁 keypad/fiveway/accelerometer（dmesg 可见 lock/unlock）；
  lvgui 轮询 `/proc/keypad` → 回调 `on_lock()`，锁定显示 `/mnt/us/ui/lock.gray`，解锁恢复原界面。
- **换锁屏图**（详见 `agentkit/kindle/boot/lock/README.md`）：
  ```bash
  python3 agentkit/kindle/boot/lock/make_lock.py ~/图片.png      # -> lock.gray (824x1200 灰度)
  scp -O agentkit/kindle/boot/lock/lock.gray kindle:/mnt/us/ui/lock.gray
  cd agentkit/kindle/boot/test && ./kui lock on    # 测试；./kui lock off 解锁
  ```
  文件缺失/大小不对时自动回退为文字锁屏；换图无需重启。
- agent 自动化：`ui_info()/ui_state()/tap(name|code)/ui_dump()`；主机工具 `boot/test/kui`，冒烟测试 `boot/test/smoke.lua`（pass=15/fail=0）
- 文本指令（语音/无障碍）：设备端原生通道 `/tmp/ui_say`，每行一条中文指令（读某本书/下一页/跳到第N页/字号大…），由 `init.lua` 的 `cmd()` 解析；`kui say "下一页"`。
- AI 闭环测试（截图→看界面→改→回归）：见 `boot/test/README.md`；`ui.flush()` 保证截图同步，`imgdiff.py` 做像素回归，`smoke.lua` 当前 pass=25/fail=0。

### ⚠️ 关键 bug 修复（血泪）
LVGL 只靠 `lv_timer_handler()` **不会把后续帧推送到 e-ink**（首帧后画面冻结）。
**正解**：UI 变化时手动 **`lv_obj_invalidate(lv_scr_act()); lv_refr_now(NULL);`** 强制同步重绘，再写灰度 PNG 调 `eips`。
同样容易踩的坑：LVGL **必须外部喂 tick**（每次循环 `lv_tick_inc(dt)`），否则 `lv_timer_handler()`
的定时器永不触发 → **按键读取回调一次都不会被调用**（表现为"按键完全没反应"）。
曾误判为驱动/锁的问题并外挂 keyd；清掉 keyd 后按键全失效才定位到 tick。

### 产物
```
/mnt/us/lvgui                      # 单体(LVGL+LuaJIT+FreeType, musl 静态, ~2.0MB)
/mnt/us/ui/{init.lua, font.ttf,    # init.lua=书架+阅读器; 字体
            books/<书名>.txt,       # 预解析的书文本
            start.sh, open.sh}      # 启停 / 交接
FIFO /tmp/ui.cmd  ·  事件 /mnt/us/ui/events
```

### 编译（主机）
```bash
cd /opt/my-agent/agentkit/kindle/boot/src && sh build.sh     # 产物 ./lvgui
# 依赖源码树默认 /opt/kindle-deps/{lvgl,luajit,ft-out}；可用 LVGL_SRC/LUAJIT_DIR/FT_OUT 覆盖
```

### 目录（应用层/内核层分离，便于回滚）
```
/opt/my-agent/agentkit/kindle/boot/src/   # lvgui.c lv_conf.h build.sh start.sh open.sh lvgui lvgui.prev
/opt/my-agent/agentkit/kindle/boot/lua/   # init.lua app.lua（改界面只动这里）
/opt/kindle-deps/                         # 依赖源码树 lvgl/ luajit/ freetype/ ft-out/
```

### agent 驱动示例
```bash
kx ssh kindle 'printf "shelf()\n" > /tmp/ui.cmd'              # 回书架
kx ssh kindle 'printf "open_book(\"异类.mobi\")\n" > /tmp/ui.cmd'  # 打开书
kx ssh kindle 'printf "on_key(\"right\")\n" > /tmp/ui.cmd'    # 下一页
```
