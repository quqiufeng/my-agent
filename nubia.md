# Nubia Z18 (NX606J) — LineageOS 22.2 刷机记录

> 创建：2026-10-20  
> 更新：2026-10-20  
> 当前状态：**已成功刷入并启动 LineageOS 22.2（Android 15）**；关键分区已 EDL 备份。  
> 一句话结论：**Z18 可以刷成功**；决定成败的是 **V2.31 modem 固件 + Nubia fastboot unlock flag + 格式化 /data**，不是 TWRP/OTG。

---

## 零、实测结论（2026-10-20，成功）

- **可以刷成功**：LineageOS Recovery 显示 22.2（`nx606j`），安装后已进入系统。
- **可靠 EDL 入口**：bootloader 菜单 **`boot to edload`**；工程线按钮和 `adb reboot edl` 都不稳定，只作备选。
- **正确 loader**：`0008b0e100010000_6c1ed0375298d9a4_fhprg.bin`（HWID `0x0008b0e100040000`，PK_HASH `0x6c1ed...`）。通用 SDM845 loader 会超时/掉线。
- **LineageOS 的固件校验**不是看系统版本，而是：
  `nubia.verify_modem("2020-06-17 00:08:25")`
  必须让 `modem` 达到 V2.31。官方 OTA 的 `NON-HLOS.bin` 内含 `MPSS.AT.4.0_V231`。
- **不需要先刷完整 2.3G 官方 OTA**：本次只通过 EDL 写 V2.31 的 `modem/xbl/tz/hyp/...` 等固件，再写自定义 ABL + Lineage Recovery，直接 sideload 成功。
- **TWRP 不是必需的**；原 TWRP 下载链接已 404，XDA 帖子也已关闭。
- **`Nubia fastboot unlocked` 必须为 true**：即使 `fastboot getvar unlocked` 返回 `yes`，只要 `fastboot oem device-info` 显示 `Nubia fastboot unlocked: false`，LineageOS 就起不来、会回到 Recovery。
- **`set_policy_failed:/data/vendor` 不是刷机失败**：切换 ROM 后常见，执行 **Factory data reset / Format data** 即可。
- **fastboot 刷 64MB recovery 会报 `Protocol error`**；大镜像统一走 EDL。
- **`printgpt` 不要加 `--maxpayload`**，否则只会打印帮助。

---

## 一、结论

- Z18 **不能**刷成熟的桌面级 Linux（Ubuntu/Debian/postmarketOS/Ubuntu Touch）。
- Z18 **可以**刷 LineageOS：官方支持，代号 `nx606j`，当前主线 **22.2（Android 15）**。
- 本次实际成功路径：
  1. EDL 备份关键分区；
  2. EDL 写 V2.31 固件（重点是 `modem`）；
  3. EDL 写自定义 ABL + Lineage Recovery；
  4. 设置 Nubia fastboot unlock flag；
  5. Factory data reset；
  6. sideload LineageOS 22.2。
- 最高危步骤仍是 **EDL 写 `xbl`/`abl` 等 bootloader 分区**；通信不稳不要写。
- 手机现已成功运行 LineageOS；若要回官方系统，使用 EDL 备份恢复。

---

## 二、设备与当前状态

| 项目 | 值 |
|---|---|
| 型号 | Nubia Z18 / NX606J |
| SoC | Qualcomm SDM845（骁龙 845） |
| 当前系统 | LineageOS 22.2（Android 15），已启动 |
| 原厂指纹 | `nubia/NX606J/NX606J:8.1.0/OPM1.171019.026/nubia11081321:user/release-keys` |
| 目标固件 | NubiaUI V2.31 / `nubia06170009` |
| 内存/存储 | 6/8GB RAM，64/128GB UFS 2.1 |
| Bootloader | `Device unlocked: true`；`Nubia fastboot unlocked: true`；`Verity mode: true`；`secure: yes` |
| 当前 Recovery | Lineage Recovery 22.2 |
| 关键备份 | persist / modem / abl / boot / recovery / modemst1 / modemst2 / fsg / fsc；新增 xbl / xbl_config / tz / hyp / cmnlib / keymaster / dsp / bluetooth / aop / qupfw / msadp / apdp / devcfg / ImageFv / splash |
| 数据 | 已格式化（刷机要求） |

---

## 三、参考链接

- 设备页：<https://wiki.lineageos.org/devices/nx606j/>
- 安装页：<https://wiki.lineageos.org/devices/nx606j/install/>
- 下载页：<https://download.lineageos.org/devices/nx606j>
- 自定义 ABL（官方安装页链接）：
  <https://androidfilehost.com/?fid=10620683726822060955>
- EDL 工具（bkerler/edl）：
  <https://github.com/bkerler/edl>
- 内核源码：
  <https://github.com/LineageOS/android_kernel_nubia_sdm845>

> 版本和链接可能变化；以官方安装页当前内容为准。

---

## 四、关键修正

### 1. 解锁要检查两个状态

命令：

```bash
fastboot oem nubia_unlock NUBIA_NX616J
```

注意是 **NX616J**，不是 NX606J。执行后必须检查：

```bash
fastboot oem device-info
```

期望：

```text
Device unlocked: true
Nubia fastboot unlocked: true
```

本次踩坑：`unlocked: yes` 但 `Nubia fastboot unlocked: false`，sideload 后重启一直回 Recovery；执行上面的 `nubia_unlock` 后设为 true 才正常启动。

### 2. `edl detect` 不存在

bkerler/edl 没有 `detect` 子命令。验证通信/分区表：

```bash
edl.py printgpt --memory=ufs --lun=1 --loader=<loader>
edl.py printgpt --memory=ufs --lun=4 --loader=<loader>
```

### 3. 固件版本看 modem，不看系统

LineageOS 安装脚本里的校验：

```text
nubia.verify_modem("2020-06-17 00:08:25")
```

验证 V2.31：

```bash
strings -a NON-HLOS.bin | grep -E 'MPSS.AT.4.0_V231|MPSS.AT.4.0.c2-00922'
```

必须出现 `MPSS.AT.4.0_V231`。

### 4. 大镜像不要走 fastboot

`fastboot flash recovery recovery.img`（64MB）本次报：

```text
Write to device failed in SendBuffer() (Protocol error)
```

改用 EDL：

```bash
edl w recovery recovery.img --memory=ufs --lun=4 --loader=<loader>
```

---

## 五、前置条件

- [ ] 电量 50% 以上。
- [ ] 接受解锁/换 ROM 会清空用户数据。
- [ ] 已准备并能识别 **EDL 9008**。
- [ ] 已确认 **正确 loader**，`printgpt` 稳定。
- [ ] 已备份关键分区（至少 persist / modem / abl / boot / recovery / modemst1 / modemst2 / fsg / fsc / xbl / xbl_config）。
- [ ] 已下载并校验：
  - [ ] 官方 OTA `NX606-update-V2.31.zip`
  - [ ] LineageOS 22.2 `nx606j` ROM ZIP
  - [ ] LineageOS Recovery `recovery.img`
  - [ ] 自定义 ABL `abl-z18-custom.elf`
- [ ] 优先使用主板后置 USB 2.0 口，不用前置口/Hub。

---

## 六、文件与工具位置

| 文件/工具 | 路径 |
|---|---|
| EDL 工具 | `~/nubia-recovery/edl-tool` |
| Python venv | `~/nubia-recovery/edlvenv` |
| 正确 loader | `~/nubia-recovery/Loaders/0008b0e100010000_6c1ed0375298d9a4_fhprg.bin` |
| 原厂 ABL 备份 | `~/nubia-recovery/abl-stock.elf` |
| 自定义 ABL | `~/nubia-recovery/abl-z18-custom.elf` |
| V2.31 固件 | `~/nubia-recovery/firmware/v231/` |
| LineageOS ROM | `~/nubia-recovery/los/lineage-22.2-20261016-nightly-nx606j-signed.zip` |
| LineageOS Recovery | `~/nubia-recovery/los/recovery.img` |
| 原备份 | `192.168.1.68:~/nubia-recovery/backup/` |
| 写前备份 | `192.168.1.68:~/nubia-recovery/backup-pre-v231/` |
| 写后校验 | `192.168.1.68:~/nubia-recovery/verify-post-v231/` |
| 小机箱 | `192.168.1.68:~/nubia-recovery/` |
| 本文档 | `/opt/my-agent/nubia.md`；镜像 `~/nubia-recovery/NUBIA_Z18_LINEAGEOS.md` |

校验值：

```text
OTA NX606-update-V2.31.zip
ba948e7f41728582c6ce2a2c75f64ad01a415ebdeb3ecdaf8449529d5f455efd

NON-HLOS.bin (V2.31)
26e0f5f8784ebdd0a05973a4751c3b7aab06841b10cb0dc9544371e768aa3f63

LineageOS 22.2 ROM
e00a0130fb4dbb5969b19f5d91d8e7c4a3daf7426814e2e67f07a3db7dbc74c1

LineageOS Recovery
cc67f2c914cff46ee2fdb6184ffad4f7eb0f6c6305f966256c7887df95807d5b

自定义 ABL
329932894ada75fdf7bccfceed9fd0cd80fbec869efbd48bf43a1d700ccd9571
```

---

## 七、成功流程（实际执行）

> 每一步确认成功后再继续；任何一步失败立即停止，不要强行继续。

### 步骤 1：进入 EDL 9008

优先 bootloader 菜单 **`boot to edload`**。目标：

```text
05c6:9008 Qualcomm ... QDL mode
```

### 步骤 2：验证 EDL + 备份

```bash
cd ~/nubia-recovery
L=Loaders/0008b0e100010000_6c1ed0375298d9a4_fhprg.bin

./edlvenv/bin/python edl-tool/edl.py printgpt \
  --memory=ufs --lun=1 --loader="$L"

./edlvenv/bin/python edl-tool/edl.py printgpt \
  --memory=ufs --lun=4 --loader="$L"
```

能稳定读到 GPT、不超时，才继续。写前至少备份：

```bash
mkdir -p backup-pre-v231

./edlvenv/bin/python edl-tool/edl.py r xbl backup-pre-v231/xbl.img \
  --memory=ufs --lun=1 --loader="$L"
./edlvenv/bin/python edl-tool/edl.py r xbl_config backup-pre-v231/xbl_config.img \
  --memory=ufs --lun=1 --loader="$L"

./edlvenv/bin/python edl-tool/edl.py r tz backup-pre-v231/tz.img \
  --memory=ufs --lun=4 --loader="$L"
# 同理：hyp / cmnlib / cmnlib64 / keymaster / dsp / bluetooth /
#       aop / qupfw / msadp / apdp / devcfg / ImageFv / splash
```

### 步骤 3：写 V2.31 固件（关键）

从官方 OTA 解出：

| 源文件 | 分区 | LUN |
|---|---|---|
| `xbl.elf` | `xbl` | 1 |
| `xbl_config.elf` | `xbl_config` | 1 |
| `tz.mbn` | `tz` | 4 |
| `hyp.mbn` | `hyp` | 4 |
| `NON-HLOS.bin` | `modem` | 4 |
| `cmnlib.mbn` | `cmnlib` | 4 |
| `cmnlib64.mbn` | `cmnlib64` | 4 |
| `keymaster64.mbn` | `keymaster` | 4 |
| `dspso.bin` | `dsp` | 4 |
| `BTFM.bin` | `bluetooth` | 4 |
| `aop.mbn` | `aop` | 4 |
| `qupv3fw.elf` | `qupfw` | 4 |
| `dp_MSA_signed.mbn` | `msadp` | 4 |
| `dp_AP_signed.mbn` | `apdp` | 4 |
| `devcfg.mbn` | `devcfg` | 4 |
| `imagefv.elf` | `ImageFv` | 4 |

逐项写：

```bash
cd ~/nubia-recovery
L=Loaders/0008b0e100010000_6c1ed0375298d9a4_fhprg.bin

./edlvenv/bin/python edl-tool/edl.py w xbl firmware/v231/xbl.elf \
  --memory=ufs --lun=1 --loader="$L"
./edlvenv/bin/python edl-tool/edl.py w xbl_config firmware/v231/xbl_config.elf \
  --memory=ufs --lun=1 --loader="$L"

./edlvenv/bin/python edl-tool/edl.py w modem firmware/v231/NON-HLOS.bin \
  --memory=ufs --lun=4 --loader="$L"
# 其余按上表逐项写；全部写完后做读回校验。
```

> 本次 `NON-HLOS.bin` 写入后读回，确认含 `MPSS.AT.4.0_V231`。  
> 不要写 `modemst1/modemst2/persist`，这些是校准/持久分区。

### 步骤 4：写自定义 ABL + Lineage Recovery

```bash
./edlvenv/bin/python edl-tool/edl.py w abl abl-z18-custom.elf \
  --memory=ufs --lun=4 --loader="$L"

./edlvenv/bin/python edl-tool/edl.py w recovery los/recovery.img \
  --memory=ufs --lun=4 --loader="$L"

./edlvenv/bin/python edl-tool/edl.py reset --loader="$L"
```

> `reset` 可能报 `USBError(5)`，设备实际会重启。  
> 不要写 OTA 里的原厂 `abl.elf`；本次用的是自定义 ABL。

### 步骤 5：设置 Nubia fastboot unlock flag

手机进 Fastboot 后：

```bash
fastboot oem nubia_unlock NUBIA_NX616J
fastboot oem device-info
```

必须看到：

```text
Device unlocked: true
Nubia fastboot unlocked: true
```

### 步骤 6：进 Lineage Recovery，先格式化 data

- 关机，按住 **音量上 + 电源** 进 Recovery。
- 如果出现自定义 ABL 菜单，选 **Recovery**。
- 选 **Factory data reset / Format data**。
- 本次未先格式化时，重启出现：
  `Can't load Android system... Reason: set_policy_failed:/data/vendor`
  **不要点 Try again**，直接 Factory data reset。

### 步骤 7：sideload LineageOS

1. Recovery → **Apply update** → **Apply from ADB**。
2. 主机：

```bash
adb -d sideload los/lineage-22.2-20261016-nightly-nx606j-signed.zip
```

3. 传输中可能只显示到 ~47%，最后出现 `Total xfer: 1.00x`，这是正常的。
4. 安装完成后选 **Reboot system now**。
5. 首次启动 2–5 分钟；期间不要断电。

### 步骤 8：如果重启又回 Recovery

按顺序检查：

1. `fastboot oem device-info` 的 `Nubia fastboot unlocked` 是否为 `true`；不是就重新执行 `fastboot oem nubia_unlock NUBIA_NX616J`。
2. 是否已 Factory data reset；`/data/vendor` 报错必须格式化。
3. 重新进 Recovery 看 sideload 是否真正完成（不要只看主机进度条）。

---

## 八、刷后验证

- [ ] 系统版本：LineageOS 22.2 / Android 15
- [ ] 通话/短信/移动数据
- [ ] Wi-Fi/蓝牙
- [ ] 相机（前后）
- [ ] 指纹
- [ ] 传感器（重力/距离/光线/指南针）
- [ ] USB OTG
- [ ] 充电/续航
- [ ] 双卡（如使用）

---

## 九、故障排查

### `set_policy_failed:/data/vendor`

切换 ROM 后 `/data` 旧数据/SELinux 策略冲突。  
处理：Recovery → **Factory data reset**，不要反复 Try again。

### 重启一直回 Recovery

优先查 `Nubia fastboot unlocked`：

```bash
fastboot oem device-info
```

不是 `true` 就：

```bash
fastboot oem nubia_unlock NUBIA_NX616J
```

然后再检查是否已格式化 data。

### sideload 报固件不满足

```text
This package requires firmware from nubiaUI NX606J_CN_Common_V2.31 or newer
```

说明 `modem` 还不是 V2.31。检查：

```bash
strings -a NON-HLOS.bin | grep MPSS.AT.4.0_V231
```

并重写 `modem`。

### EDL `Device detected` 后 bulk timeout

| 可能原因 | 处理 |
|---|---|
| USB 端口/线不稳 | 换主板后置 USB 2.0 口；换能传数据的线 |
| loader 不匹配 | 只用本文的 `0008b0e1...6c1ed...` |
| EDL 入口不干净 | 优先 `boot to edload` |
| 驱动占用 | Linux 解绑 `qcserial`；Windows 确认无黄色感叹号 |
| 工具兼容性 | 换 bkerler/edl 版本 |

### 完全无枚举

先修线/端口/驱动/进入模式；**不要写入**。

---

## 十、救砖

适用：写错 ABL、系统起不来、只能进 EDL。

1. 进纯净 EDL 9008。
2. 用正确 loader 连接。
3. 写回备份：

```bash
./edlvenv/bin/python edl-tool/edl.py w abl backup/abl.img \
  --memory=ufs --lun=4 --loader="$L"
```

4. 必要时写回 `boot/recovery/modem/persist/modemst1/modemst2/fsg/fsc`。
5. `reset` 后进官方系统。
6. 先测试通话/短信/数据/Wi-Fi，再决定是否继续刷。

> 本次没有使用 QFIL；Linux + EDL + 正确 loader 已足够。  
> 官方线刷仍可作为最后手段，但不再是首选。

---

## 十一、备份

本次已完成并校验：

- 原备份：`persist`、`modem`、`abl`、`boot`、`recovery`、`modemst1/2`、`fsg`、`fsc`
- 写 V2.31 前新增：`xbl`、`xbl_config`、`tz`、`hyp`、`cmnlib`、`cmnlib64`、`keymaster`、`dsp`、`bluetooth`、`aop`、`qupfw`、`msadp`、`apdp`、`devcfg`、`ImageFv`、`splash`
- 位置：**只保留小机箱一份**：
  `192.168.1.68:~/nubia-recovery/backup/`、`192.168.1.68:~/nubia-recovery/backup-pre-v231/`。  
  不再复制到本机/NAS。
- 写后读回：`recovery.img` SHA256 完全一致；`modem/xbl/xbl_config/abl` 前 N 字节与源文件一致，尾部差异只是分区填充。

> 用户数据已在刷机时清空；照片/文件需从个人备份恢复。

---

## 十二、执行清单

- [x] 备份数据
- [x] 确认官方系统功能正常
- [x] 准备并校验 ABL / ROM / Recovery / Firmware / Loader
- [x] 进入 EDL，`printgpt` 稳定
- [x] 写 V2.31 固件（含 modem）
- [x] 写自定义 ABL + Lineage Recovery
- [x] 设置 Nubia fastboot unlock flag
- [x] Factory data reset
- [x] Sideload LineageOS 22.2
- [x] 首次启动成功

---

## 十三、最终建议

- **已成功**：Z18 现在可以日常运行 LineageOS 22.2；保留 EDL 备份和正确 loader。
- **不要重复刷**：除非有明确需求；每次写 bootloader 分区都有风险。
- **要回官方**：用 `backup/` 里的 `abl/boot/recovery/modem` 等 EDL 写回。
- **要桌面 Linux**：Z18 目前没有成熟日常方案，不建议。

> 记住：**通信不稳不写，文件不校验不写，救砖备份不在手边不刷。**
