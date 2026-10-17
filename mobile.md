# 把 Android 手机改造成「开机即自己的 UI」的 Linux 设备

> 设备：**vivo Y31s 标准版（V2068A）**，Android 11 / arm64 / 无 root。
> 目标：开机不经过 Android 桌面，直接进入自研 UI（LVGL+LuaJIT，见 `agentkit/kindle/`）。
> 本文记录整个过程、原理与踩坑，所有结论都在真机上验证过。

---

## 0. 结论先行

- **不能刷 Linux、不能 root**（bootloader 锁死 + 无主线移植），强行解锁=变砖风险。
- 可行路线是 **Termux + proot Debian**（无 root 的用户态 Linux），性能约为原生 80~90%。
- 显示用 **Xvfb + x11vnc + AVNC**（Termux:X11 在本机黑屏）。
- UI 层加一个 **SDL2 后端**，同一份 Lua 界面代码在 Kindle（e-ink）和手机（LCD）上都能跑。
- 开机用 **Termux:Boot** 拉起整套环境，再 `am start vnc://...` 直接全屏进 UI。
- vivo 有三道厂商限制必须放行：**自启动**、**后台弹出界面**（关键）、**悬浮窗**。

最终效果：开机 → 无锁屏 → 自动进入自研阅读器 UI；`ssh phone` 可远程维护。

---

## 1. 设备与环境

| 项 | 值 |
|---|---|
| 型号 | vivo V2068A（Y31s 标准版） |
| 系统 | Android 11（SDK 30，OriginOS/Funtouch） |
| CPU/ABI | arm64-v8a（兼容 armeabi-v7a） |
| 内存 | 5.7 GB |
| 屏幕 | 720×1600 @320dpi |
| 存储 | 128 GB（可用 ~82 GB） |
| root | **无**（`su` 不存在） |
| 网络 | Wi-Fi `192.168.1.99`（DHCP，会变，用 `kscan` 扫） |

主机：Ubuntu，`adb` + `ssh`，`~/opt/arm-linux-musleabi-cross`（给 Kindle 的交叉链，与本文无关）。

---

## 2. 为什么不能 root / 刷 Linux

1. **bootloader 锁死**：vivo 官方不提供 `fastboot oem unlock`，也没有公开救砖包。
   没有解锁就写不了 boot/系统分区；所谓第三方解锁多为付费灰色工具，机型支持差、失败即砖。
2. **没有主线移植**：postmarketOS / Ubuntu Touch / Mobian 都没有 V2068A 的设备树与内核，
   屏幕、触摸、音频、基带驱动全要自己写，不是"刷"，是"造"。
3. **root 也解决不了全部**：厂商的安装验证、系统应用保护是另一套策略。

> 所以本文全部在**无 root**前提下完成。

---

## 3. 技术路线

```
Android 11（原封不动）
└─ Termux（普通 App，F-Droid 版）
   ├─ sshd（8022，免密 key）
   ├─ Termux:Boot → ~/.termux/boot/start.sh（开机自启）
   └─ proot Debian 12 arm64（用户态 Linux，无需 root）
      ├─ Xvfb :1（824×1200×24，-ac 关访问控制）
      ├─ x11vnc :5900（-nopw）
      └─ /root/lv/lvgui（LVGL+LuaJIT，SDL2 后端）
         界面脚本 /mnt/us/ui/init.lua（与 Kindle 同一套）
手机屏 ← AVNC（com.gaurav.avnc）连 vnc://127.0.0.1:5900
```

要点：**proot** 用 ptrace 拦截系统调用，把进程的 `/` 重定向到 rootfs，实现"假 chroot"；
不需要 root，但会有一些系统调用/性能开销（实测够用）。

---

## 4. 分步过程与原理

### 4.1 开启 ADB 与 USB 权限

1. 设置 → 关于手机 → 连点「版本号」7 次 → 开发者选项
2. 打开「USB 调试」（vivo 另有「USB 调试（安全设置）」，模拟输入需要）
3. 插 USB → 手机弹「允许 USB 调试吗」→ 勾「始终允许」→ 允许
4. USB 用途改成「传输文件 (MTP)」

**原理/排错**：`adb devices` 为空时，用 `lsusb` 看接口。
- `bInterfaceClass=6 (PTP)`/`8 (Mass Storage)` → 只有 MTP/U 盘，**没有 ADB 接口**（ADB 是 `ff/42/01`），说明调试没开或没授权。
- reboot 后出现 `no permissions (missing udev rules?)` → 主机缺 udev 规则：

```bash
sudo tee /etc/udev/rules.d/51-android-vivo.rules <<'X'
SUBSYSTEM=="usb", ATTR{idVendor}=="2d95", MODE="0666", GROUP="plugdev"
X
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### 4.2 安装 Termux（vivo 会拦）

```bash
# F-Droid 版（Play 版已停更）
VC=$(curl -s https://f-droid.org/api/v1/packages/com.termux | python3 -c 'import json,sys;print(json.load(sys.stdin)["suggestedVersionCode"])')
curl -L -o termux.apk "https://f-droid.org/repo/com.termux_${VC}.apk"
adb install -r termux.apk
```

**踩坑**：vivo 会弹「安全守护提示」并要求**指纹/锁屏密码**验证，`adb install` 会报
`INSTALL_FAILED_ABORTED: User rejected permissions`。解决办法：用 uiautomator 拿到控件坐标，
勾选「已了解应用的风险检测结果」→「继续安装」→「锁屏密码验证」→ 输密码。
（也可以在设置里关掉「外部来源应用验证」，但每台机器入口不一样。）

如果 adb 安装仍被拒，可 `adb push` 到 `/sdcard/Download/` 手动点安装。

### 4.3 免密 SSH

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_phone -N ''
# Termux 里：
pkg install -y openssh
mkdir -p ~/.ssh && echo '<pubkey>' > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
sshd        # 监听 8022
```

主机 `~/.ssh/config`：

```
Host phone
    HostName 192.168.1.99
    Port 8022
    User u0_a171
    IdentityFile ~/.ssh/id_ed25519_phone
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

**原理**：Termux 的 sshd 不校验用户名（任意名字都能登，实际运行在 App 的 uid 下）。
IP 会变，用 `kscan --rebind` 扫描 8022 端口并自动改配置。

### 4.4 proot Debian（Docker Hub 被墙）

`proot-distro 5.x` 默认从 Docker Hub 拉镜像，国内会 `Connection reset by peer`。
改用**清华 LXC 镜像**的 Debian rootfs（arm64）：

```bash
URL=https://mirrors.tuna.tsinghua.edu.cn/lxc-images/images/debian/bookworm/arm64/default/20261016_05:24/rootfs.tar.xz
proot-distro install -n debian "$URL"      # 90.6 MiB
proot-distro login debian
```

容器内换源并装依赖：

```bash
sed -i 's|deb.debian.org|mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list
apt update && apt install -y build-essential libsdl2-dev libfreetype-dev \
    luajit libluajit-5.1-dev xvfb x11vnc xterm
```

> **原理**：LXC 的 `rootfs.tar.xz` 就是标准 Debian 根文件系统，proot-distro 支持从 URL 安装。

### 4.5 显示：Termux:X11 黑屏 → 改 VNC

先试了官方 **Termux:X11**（APK + `termux-x11-nightly` 包）：
X server 正常、窗口树里能看到 `xeyes`，但手机屏幕上**始终黑屏**（surface 不刷新），
`xsetroot -solid red` 也不显示。换机成本太高，放弃。

改用 **Xvfb + x11vnc + AVNC**：

```bash
# 容器内
Xvfb :1 -screen 0 824x1200x24 -ac &
x11vnc -display :1 -nopw -forever -shared -rfbport 5900 &
# 手机装 AVNC（F-Droid: com.gaurav.avnc），连 127.0.0.1:5900
```

**两个关键点**：
1. `-ac` 关闭 X 访问控制，否则 x11vnc 连不上（报 Xauthority 相关错误）。
2. **proot 会话一退出，后台进程会被杀**。必须让会话常驻：

```bash
nohup proot-distro login debian -- bash -c \
  "Xvfb :1 -screen 0 824x1200x24 -ac & sleep 1; x11vnc ... & sleep 100000" >/dev/null 2>&1 &
```

AVNC 支持 URI，可直接打开并连接：

```bash
am start -a android.intent.action.VIEW -d "vnc://127.0.0.1:5900"
```

### 4.6 移植 UI 层（SDL2 后端）

同一份 `lvgui.c`（C）+ Lua 界面，加 `-DUSE_SDL2`：

- `flush_cb` 仍然把 LVGL 画到 `g_gray`，SDL 版本再上传成纹理、`SDL_RenderPresent` 显示；
- 不再走 `eips`/PNG/evdev；
- 键盘事件映射成与 Kindle **相同的扫描码**（↑122 ↓123 ←105 →106 回车92 空格57 …），
  所以 `init.lua` 一行不用改；
- `ui.flush()` 退化为"立即重绘上屏"。

```bash
gcc -O2 -DUSE_SDL2 -DLV_CONF_INCLUDE_SIMPLE -I lvgl -I lvgl/src -I . \
  $(pkg-config --cflags sdl2 freetype2) $(find lvgl/src -name '*.c') lvgui.c \
  $(pkg-config --libs sdl2 freetype2) -I/usr/include/luajit-2.1 -lluajit-5.1 -lm -ldl -o lvgui
```

**原理**：UI 逻辑全在 Lua；C 只是"渲染 + 输入 + 管道"的适配层。
换显示后端（e-ink/窗口）不影响业务代码，这就是可移植的收益。

> Lua 层在 Linux 上会有 `echo unlock > /proc/keypad` 报错（目录不存在），无害。

### 4.7 开机自启与 kiosk

装 **Termux:Boot**（`com.termux.boot`），它会在开机后执行 `~/.termux/boot/*.sh`。
然后再打开一次 Termux:Boot 注册接收器。

`~/.termux/boot/start.sh`：

```bash
#!/data/data/com.termux/files/usr/bin/bash
exec >> ~/boot.log 2>&1
echo "=== $(date) boot ==="
export PATH=/data/data/com.termux/files/usr/bin:$PATH
termux-wake-lock
sshd
pkill Xvfb; pkill x11vnc; pkill lvgui
nohup proot-distro login debian -- bash -c \
  "Xvfb :1 -screen 0 824x1200x24 -ac & sleep 1; x11vnc -display :1 -nopw -forever -shared -rfbport 5900 & sleep 2; DISPLAY=:1 /root/lv/lvgui & sleep 100000" >/dev/null 2>&1 &
for i in $(seq 1 40); do
  if (echo > /dev/tcp/127.0.0.1/5900) 2>/dev/null; then
    am start -a android.intent.action.VIEW -d "vnc://127.0.0.1:5900" && break
  fi
  sleep 3
done
```

> **不要**在脚本里 `pkill sshd`：如果这个脚本是通过 SSH 手动跑的，会把你自己踢下线。

### 4.8 vivo 的三道坎（重点）

| 限制 | 位置 | 作用 |
|---|---|---|
| 自启动 | `com.vivo.permissionmanager/.activity.BgStartUpManagerActivity` | 允许 Termux / Termux:Boot 开机启动 |
| **后台弹出界面** | 权限管理 → 权限 → 后台弹出界面 | **允许 Termux 在后台启动 Activity**（关键） |
| 悬浮窗 | 权限管理 → 权限 → 悬浮窗 | 辅助 |

**踩坑过程**：
- 开机脚本能跑（`boot.log` 有记录）、sshd 和 VNC 都起来了，但 AVNC 不弹出。
- `am start` 返回 `Error: Activity not started, unknown error code 4002`。
- 手动在 Termux 前台执行 `am start` 却成功 → 说明是 **Android 的后台启动 Activity 限制（BAL）**。
- 先试 `appops set com.termux SYSTEM_ALERT_WINDOW allow`（悬浮窗）——不够。
- 最终在 vivo 的「权限管理 → 后台弹出界面」里允许 Termux / AVNC，`am start` 立刻成功（rc=0）。

> 原理：Android 10+ 禁止后台应用启动 Activity；部分厂商（vivo）把这条做成了独立权限，
> 即使有 `SYSTEM_ALERT_WINDOW` 也仍然拦截。

### 4.9 去掉锁屏

vivo 的「无密码」默认仍是**滑动**锁屏，开机会停在那。
用 adb 直接禁用锁屏（无密码时不需要提供凭据）：

```bash
adb shell locksettings set-disabled true
adb shell locksettings get-disabled   # true
```

### 4.10 保活

```bash
termux-wake-lock                                   # Termux 内
adb shell dumpsys deviceidle whitelist +com.termux # 免 Doze
adb shell dumpsys deviceidle whitelist +com.gaurav.avnc
adb shell settings put system screen_off_timeout 2147483647   # 屏幕常亮
```

---

## 5. 逆向方法（可复用到别的机型）

1. **找隐藏 Activity**：
   ```bash
   adb shell dumpsys package <pkg> | grep -oE '<pkg>/\.[A-Za-z.]+' | sort -u
   ```
   这次就是这样找到 `BgStartUpManagerActivity` 和 `PurviewTabActivity` 的。
2. **驱动界面**：`uiautomator dump` 拿控件的 `text`/`bounds`，再 `input tap x y` / `input text`。
   比盲点可靠得多（本次装 App、开权限全靠这套）。
3. **判断被谁拦**：先看返回值/异常。
   - `INSTALL_FAILED_ABORTED: User rejected permissions` → 厂商安装验证
   - `DELETE_FAILED_USER_RESTRICTED` → 系统应用受保护，无 root 无法卸载
   - `unknown error code 4002` → 后台启动 Activity 被拦
4. **看 USB 接口**：`lsusb -v` 看 `bInterfaceClass`，`ff/42/01` 才是 ADB。
5. **厂商设置项**：`设置` 里搜不到时，直接 `am start -n <pkg>/<activity>` 跳进去。

---

## 6. 速查命令

```bash
# 连接
ssh phone                                   # 免密（~/.ssh/config 里的 Host phone）
kscan                                       # 扫局域网 8022
kscan --rebind                              # IP 变了，自动改配置

# 状态
ssh phone 'pgrep -a lvgui; pgrep -a Xvfb; (echo > /dev/tcp/127.0.0.1/5900) && echo OK'
ssh phone 'tail -20 ~/boot.log'

# 重启 UI
ssh phone 'pkill lvgui'                     # 只杀界面（VNC 还在）
ssh phone 'bash ~/.termux/boot/start.sh'    # 整套重来（会重开 AVNC）

# 驱动 UI（容器内 FIFO）
ssh phone 'proot-distro login debian -- bash -c "printf \"open_book(\\\"异类.mobi\\\")\n\" > /tmp/ui.cmd"'
```

---

## 7. 排错表

| 现象 | 原因 | 解决 |
|---|---|---|
| `adb devices` 空 | 没开 USB 调试 / 未授权 / 只有 MTP | 开发者选项打开调试，重插，允许授权 |
| `no permissions (missing udev rules?)` | 主机 udev 无权限 | 加 `51-android-vivo.rules` 并 reload |
| `INSTALL_FAILED_ABORTED` | vivo 安装验证 | 勾选风险提示 + 指纹/密码；或改设置 |
| `DELETE_FAILED_USER_RESTRICTED` | 系统应用受保护 | 无 root 无解；只能设置里停用/加白名单 |
| proot 装 Debian 卡在 registry | Docker Hub 被墙 | 用清华 LXC rootfs URL |
| VNC 连不上 | x11vnc 未起 / 会话被杀 / 无 `-ac` | 常驻 proot 会话；加 `-ac` |
| Termux:X11 黑屏 | 本机 surface 不刷新 | 换 Xvfb + x11vnc + AVNC |
| 开机不自动进 UI | 自启动 / 后台弹出界面 未允许 | 两个权限都放行；看 `~/boot.log` |
| `am start` 返回 4002 | 后台启动 Activity 被拦 | vivo 权限管理里开「后台弹出界面」 |
| 开机停在滑动锁屏 | 锁屏模式是 Swipe | `locksettings set-disabled true` |

---

## 8. 安全与维护

- **VNC 无密码**（`-nopw`，监听 0.0.0.0:5900）。仅限可信局域网；要收紧可加 `-localhost`
  （AVNC 连本机，不影响使用）。
- **SSH 用密钥**，不要开密码登录。
- **回 Android**：按 Home 键（AVNC 不是桌面）。
- **恢复原状**：卸载 Termux / Termux:Boot / AVNC / Termux:X11，删 `~/.termux/boot/start.sh`，
  `locksettings set-disabled false`。

---

## 9. 未做 / 可选

- **真 root**：需要可解锁 bootloader 的机型（Pixel / 部分小米），或换 PinePhone 之类原生 Linux 手机。
- **原生帧缓冲**：无 root 拿不到 `/dev/fb0` 的写权限；VNC 是当前最稳的显示路径。
- **性能**：proot 有 ptrace 开销；如果只跑界面/服务，完全够用。
- **Android UI 换成自己的**：技术上只能"开机后立刻盖一层"，无法替换系统桌面/开机动画（需 root）。

---

## 10. Root / 刷机可行性（实测结论：不可行）

目标机型：vivo V2068A（Y31s 标准版），**MT6833（天玑 700）**。

### 10.1 实测结果

| 尝试 | 结果 |
|---|---|
| `fastboot getvar unlocked` | `no` |
| `fastboot flashing unlock` | `unknown command` |
| `fastboot oem unlock` / `unlock-go` | `unknown command` |
| `fastboot oem unlock_vivo`（BBK 工程命令） | `unknown command` |
| `fastboot flashing get_unlock_ability` | `unknown command` |
| 音量+ 插线 → mtkclient `printgpt` | 进 **Preloader**（`0e8d:20ff`），握手连续失败 |
| 音量+/- 同按 → 纯 BROM（`0e8d:0003`） | 进不去，仍停在 Preloader |

**结论**：不是"锁着"，是这台机的 **bootloader 根本没实现解锁功能**；
Preloader 侧还有 **SLA/DAA 签名认证**（mtkclient 无签名 DA，握手即失败）。

### 10.2 为什么社区方案也没用

- GitHub 有两个 PD2068 的 **TWRP 设备树**（`xxroot/twrp_vivo_PD2068`、
  `qiurigao/android_device_vivo_PD2068-TWRP`），但 **releases 为 0**，没有现成镜像，
  也没有解锁说明。
- 就算自己编译出 TWRP，**也没有写入通道**：
  - `fastboot flash` → bootloader 不支持解锁
  - MTK BROM/Preloader → SLA 认证
  - 原厂 recovery → 只接受 vivo 私钥签名的 OTA
- `ppma/fastboot` 的 `bbk unlock_vivo` 本质只是转发 `oem unlock_vivo`，
  在这台机上同样 `unknown command`。

### 10.3 若一定要 root

只剩**付费商业工具**（UnlockTool / TFM / Miracle Box / Hydra 等），特点：
- 依赖厂商或第三方的授权服务器，按年/按次收费
- 多数只支持 Windows（需虚拟机）
- 是否覆盖 V2068A / MT6833 需查其机型列表，**大概率不支持**
- 网上"免费破解版"基本带毒

**建议**：这台机放弃 root。真要 root/原生 Linux，换可解锁机型
（Pixel、部分一加/小米），或 PinePhone 这类原生 Linux 手机。

### 10.4 如果未来换到可解锁机型，通用流程

```bash
fastboot flashing unlock            # 官方解锁（会清数据）
# 提取 stock boot.img → Magisk 打补丁 → fastboot flash boot
# 或用 TWRP 设备树编译 recovery 后刷入
```

---

## 11. Nubia Z18（NX606J）记录

> 备用机，SDM845 / Android 8.1（SDK 27）/ verifiedboot green / 5.8GB RAM。
> **注意：本文档记录的是实际发生过的事，包括失败。**

### 11.1 关键操作：从原厂 recovery 进 fastboot（重点，别忘）

原厂 recovery 菜单只有四项：
`选择升级包（含 OTG） / 清理数据 / 重启手机 / 关机`

- 在 recovery 里**音量键是导航**，所以没法用「音量下 + 电源」组合。
- 正确做法：**先按住「音量下」不放**，再让它重启（选「重启手机」或「关机」，用**电源键**确认），
  音量下一直按着 → 重启后停在 **fastboot**（USB `18d1:d00d`，序列号即设备 SN）。
- 如果「关机」会自己重启（ABL 复位路径异常），也用同样办法：按住音量下让它重启。

```bash
sudo fastboot devices        # 看到 <sn> fastboot 即成功
```

### 11.2 EDL（9008）进入方式

- 系统正常时：`adb -s <sn> reboot edl`
- 关机后：**同时按住 音量＋ 和 音量－** 再插 USB（保持 8 秒）
- 出现 `05c6:9008 QDL mode` 即成功

### 11.3 已试过的东西（结论）

| 尝试 | 结果 |
|---|---|
| `fastboot oem unlock` / `flashing unlock` / `oem nubia_unlock NUBIA_NX616J`（原厂 ABL） | 全部 `unknown command` |
| 按 LineageOS wiki 刷自定义 ABL：`edl w abl abl-z18-custom.elf --memory=ufs --lun=4` | 写入成功（sector 40966） |
| 刷完后 | **系统起不来，反复重启/进 recovery；USB 不枚举一段时间** |
| recovery → fastboot（按住音量下重启） | **可以进 fastboot**，但解锁命令仍 `unknown command` |

### 11.4 文件与位置

- 自定义 ABL：`/tmp/opencode/abl-z18-custom.elf`（151552 B，来自 LineageOS wiki 的 androidfilehost 链接）
- **原厂 ABL**：`/tmp/opencode/abl-stock.elf`（135168 B，来自 GitHub `TadiT7/nubia_nx606j_dump`）
- EDL 工具：`/tmp/opencode/edl-tool`（bkerler/edl）+ `Loaders/`（bkerler/Loaders）
- 分区表：`/tmp/opencode/gpt.txt`（`abl` 在 **LUN 4**，offset `0xa006000`，长度 `0x100000`；`ablbak` 在 `0x22ce6000`）

原厂 ABL 恢复命令：

```bash
cd /tmp/opencode/edl-tool
sudo /tmp/opencode/mtkenv/bin/python edl.py w abl /tmp/opencode/abl-stock.elf --memory=ufs --lun=4
```

### 11.5 待办（按顺序）

1. [ ] 买 **9008 深刷线**（高通工程线，支持 SDM845，带开关）
2. [ ] 线到后插上，确认主机 `lsusb` 出现 `05c6:9008`
3. [ ] 刷回原厂 ABL：
       `cd /tmp/opencode/edl-tool && sudo /tmp/opencode/mtkenv/bin/python edl.py w abl ~/abl-stock.elf --memory=ufs --lun=4`
4. [ ] 重启，确认能正常进 Android
5. [ ] 进系统后先 `adb reboot edl`，把 **全部分区 dump 备份**（`edl r <part> ...`），再考虑任何写操作
6. [ ] 备份完成后再评估解锁（正确版本的自定义 ABL / TWRP / LineageOS）
7. [ ] 若深刷线也不行 → 送修（EDL 盒子）

**已知事实（别再踩）**
- 原厂 ABL **不支持** `fastboot flash` / `download` / `getvar`，只能 `reboot` / `continue`
- 按键组合（音量+/音量-/三个键）在这台机上**触发不了 EDL**
- 数据（照片）已备份：`~/nubia_imgs`（226 个文件，1.7G）

### 11.6 经验教训（写给下次的自己）

1. **没有完整备份，不碰 bootloader。**
   这次照片备份了，但**没有 dump 分区**（尤其 `abl`/`xbl`/`boot`），出事之后没有任何回滚手段。
   正确顺序：`printgpt` → `edl r` 全分区 dump → 校验 → 才允许写。
2. **先验证写入通道，再写。**
   写之前先确认：EDL 能不能进、能不能读、能不能写、写完能不能恢复。
   这次只验证了“能读”，就假设“能写、能恢复”。
3. **确认镜像与机型/固件版本严格匹配。**
   来自第三方网盘（androidfilehost）的 ABL，没有和本机固件版本比对，
   也没检查它的签名/来源是否对应 NX606J。
4. **“能进 fastboot” ≠ “能刷机”。**
   原厂 ABL 可能不支持 `flash`/`download`/`getvar`，只有 `reboot`/`continue`。
   刷机前先用 `fastboot getvar version` 试探。
5. **不要把“应该能恢复”当成“随时能恢复”。**
   恢复路径（EDL 按键组合）必须在动手前**当场验证一遍**；
   这次是假设它能进，实际进不去，于是没有退路。
6. **对不熟悉的机型，先只读、后写。**
   能用 `edl printgpt`/`r` 做的事情，就不要先 `w`。
7. **一次只改一个变量。**
   这次同时做了：开 OEM 解锁、刷 ABL、准备解锁命令。
   出问题后无法判断是哪一步导致的。
8. **不夸口。** 说“几分钟恢复”“随时可恢复”之前，先确认前提成立。
9. **备用机也是设备。** 动 bootloader 前要明确告知风险（变砖、无法恢复），并得到确认。

---

## 12. 把手机当监控摄像头/麦克风（CamStream）

自己写的 Android App（`agentkit/camstream/`），无 root，把**前后摄像头**和**麦克风**
通过局域网 HTTP 推给任何程序。

### 12.1 接口（局域网直接可用）

```bash
curl http://192.168.1.99:8080/info           # {"current":"back","cameras":[...]}
ffplay "http://192.168.1.99:8080/video?cam=back"   # 后置 MJPEG
ffplay "http://192.168.1.99:8080/video?cam=front"  # 前置 MJPEG
ffplay "http://192.168.1.99:8080/audio"            # WAV 16k 单声道
ffmpeg -i "http://.../video?cam=back" -i "http://.../audio" -c:v libx264 -c:a aac out.mp4
```

主机侧封装：`phone-cam info|view [back|front]|audio|snap [out] [cam]|record [dir] [seg] [cam]`


### 12.2 实现要点

- Camera2 + YUV_420_888 → NV21 → JPEG（`YuvImage.compressToJpeg`），限 10fps 省 CPU
- 前后摄像头切换：`/video?cam=xxx` 触发 close→open（`camLock` 同步）
- AudioRecord 16k/16bit/mono → 共享队列 → `/audio` 输出 WAV
- 前台服务 + `PARTIAL_WAKE_LOCK`：**熄屏也推流**
- 极简 HTTP 服务（ServerSocket），多线程处理客户端

### 12.3 构建 / 安装

```bash
cd agentkit/camstream && ./build.sh        # 需 JDK 17（d8 与 JDK21 不兼容）+ SDK 34/30
adb install -r build/camstream.apk
```

**vivo 安装拦截**的两个坑：
1. 安装验证要 vivo 账号密码（账号丢失时无法通过）→ 安装前
   `adb shell am force-stop com.bbk.account`，安装弹窗里勾选「已了解风险」→「继续安装」
2. 后台启动前台服务被限制（`startForegroundCount=0`）→ 必须 `am start -n .../.MainActivity`
   起 Activity，不能只 `am startservice`

### 12.4 开机自启

`~/.termux/boot/start.sh` 里（必须在 AVNC 之前，否则监控界面会盖住阅读器）：

```bash
[ -f ~/monitor.enable ] && am start -n com.example.camstream/.MainActivity
```

`touch ~/monitor.enable` 开；删掉关。

### 12.5 已知限制

- MJPEG 带宽 ~6Mbps@10fps；要 H.264 需改 MediaCodec
- 音频只支持一个客户端（共享队列）
- 无鉴权/加密（仅可信局域网）
- 切换摄像头有 1~2 秒空窗（关旧相机会话→开新会话）
- 手机面朝下时前摄全黑（正常）
