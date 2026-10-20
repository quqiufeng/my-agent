# Nubia Z18 (NX606J) — LineageOS 22.2 刷机方案

> 创建：2026-10-20  
> 当前状态：已用官方线刷恢复 Android 8.1，ADB 已授权。  
> 原则：**通信不稳不写；文件不校验不写；救砖包不在手边不刷。**

---

## 一、结论

- Z18 **不能**刷成熟的桌面级 Linux（Ubuntu/Debian/postmarketOS/Ubuntu Touch）。
- Z18 **可以**刷 LineageOS：官方支持，代号 `nx606j`，当前主线 **22.2（Android 15）**。
- 最高危步骤：原厂 ABL 不支持 `fastboot flash`，必须先用 **EDL** 把自定义 ABL 写入 `abl` 分区（UFS，LUN 4）。
- 上次变砖的直接原因：写入了**不匹配/损坏的 ABL**，破坏引导链；不是“没 SD 卡”或“没备份”导致的。
- 手机现已恢复官方系统。**如果只求稳定主力机，建议停在官方系统；要刷就严格按官方流程。**

---

## 二、设备与当前状态

| 项目 | 值 |
|---|---|
| 型号 | Nubia Z18 / NX606J |
| SoC | Qualcomm SDM845（骁龙 845） |
| 系统 | Android 8.1.0 / SDK 27 |
| 指纹 | `nubia/NX606J/NX606J:8.1.0/OPM1.171019.026/nubia11081321:user/release-keys` |
| 内存/存储 | 6/8GB RAM，64/128GB UFS 2.1 |
| 当前模式 | 官方系统，ADB `device`（已授权） |
| 可用刷机模式 | Fastboot；EDL 9008（需验证通信稳定） |
| 上次故障 | 自定义 ABL 写入后系统起不来；EDL 曾出现 bulk 传输超时 |
| 上次恢复 | 官方线刷：重写分区 + 官方完整包 + 驱动 |

---

## 三、官方支持与参考链接

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

## 四、必须修正的三个点

### 1. 解锁命令

官方命令是：

```bash
fastboot oem nubia_unlock NUBIA_NX616J
```

注意是 **NX616J**，不是 NX606J。

### 2. `edl detect` 不是 bkerler/edl 的命令

bkerler/edl 没有 `detect` 子命令。验证通信/分区表用：

```bash
edl.py printgpt --memory=ufs --lun=4 --loader=<loader>
```

官方写 ABL 的命令是：

```bash
edl w abl abl.elf --memory=ufs --lun=4
```

### 3. 自定义 ABL 必须来自官方链接

上次很可能就是 ABL 不匹配/损坏。下载后：

```bash
sha256sum abl.elf
ls -l abl.elf
```

至少确认来源是官方安装页链接，并记录 SHA256；不确定就**不要写**。

---

## 五、前置条件（缺一不刷）

- [ ] 手机官方系统功能正常：通话、短信、移动数据、Wi-Fi、相机、指纹、传感器。
- [ ] 已移除 Google 账户，避免 FRP。
- [ ] 电量 50% 以上。
- [ ] 已备份照片/文件（解锁会清空数据）。
- [ ] 官方线刷救砖包、QFIL、9008 驱动在手边（上次恢复用的那套）。
- [ ] 下载并校验：
  - [ ] 自定义 ABL `abl.elf`
  - [ ] LineageOS 22.2 `nx606j` ROM ZIP + `.sha256`
  - [ ] LineageOS Recovery `recovery.img` + `.sha256`
  - [ ] SDM845 Firehose Loader
- [ ] 优先使用主板后置 USB 2.0 口，不用前置口/Hub。
- [ ] 接受解锁清空数据、第三方 ROM 可能有个体兼容问题。

---

## 六、文件与工具位置

本机已准备：

| 文件/工具 | 路径 |
|---|---|
| 原厂 ABL | `~/nubia-recovery/abl-stock.elf`（135168 字节） |
| EDL 工具 | `~/nubia-recovery/edl-tool` |
| EDL Loaders | `~/nubia-recovery/Loaders` |
| Python venv | `~/nubia-recovery/edlvenv` |
| 本次文档 | `~/nubia-recovery/NUBIA_Z18_LINEAGEOS.md` |

SDM845 loader 目录：

```text
~/nubia-recovery/Loaders/qualcomm/factory/sdm845_sdm850_sda845/
```

使用前先 `printgpt` 验证；如果 bulk 传输超时，停止，不要写。

---

## 七、官方刷机流程

> 每一步确认成功后再继续；任何一步失败立即停止，不要强行继续。

### 步骤 1：进入 EDL 9008

官方安装页使用：

```bash
adb -d reboot edl
```

也可以尝试硬件组合：关机后按住音量加+音量减，再插 USB。  
目标是电脑出现：

```text
05c6:9008 Qualcomm ... QDL mode
```

### 步骤 2：验证 EDL 通信（必做，只读）

```bash
cd ~/nubia-recovery
./edlvenv/bin/python edl-tool/edl.py printgpt \
  --memory=ufs --lun=4 \
  --loader=Loaders/qualcomm/factory/sdm845_sdm850_sda845/<loader>.bin
```

成功标志：

- 能读到 GPT/分区表（至少能看到 `abl`）。
- 没有 `USB bulk transfer timeout`。
- 设备不反复掉线。

失败：

- 立即停止，不写。
- 换后置 USB 2.0 口/换线/换电脑。
- 检查 loader 是否匹配 SDM845。
- 必要时改用 Windows QFIL。

> **EDL 不稳时写入，风险远大于不刷。**

### 步骤 3：写入自定义 ABL（最高危）

仅在步骤 2 稳定成功后：

```bash
edl w abl abl.elf --memory=ufs --lun=4
```

要点：

- 确认 `abl.elf` 已校验。
- 目标：`abl`，UFS，LUN 4。
- 观察进度到完成；中途超时立即停止，不要重复刷同一个文件。
- 完成后长按电源键约 10 秒重启。

### 步骤 4：解锁 Bootloader

1. 开发者选项开启 **OEM 解锁**。
2. 关机，按住音量减+电源进入 Fastboot。
3. 确认：

```bash
fastboot devices
```

4. 解锁（官方命令）：

```bash
fastboot oem nubia_unlock NUBIA_NX616J
```

5. 按手机屏幕提示确认；完成后会清空数据。
6. 重启后重新打开 USB 调试。

### 步骤 5：刷入 Lineage Recovery

```bash
fastboot flash recovery recovery.img
```

刷完不要直接进系统（会被原系统覆盖 Recovery）：

- 关机，按住音量加+电源进入 Recovery。
- 确认显示 LineageOS 标志。

### 步骤 6：刷入 LineageOS

1. Recovery → **Factory Reset** → **Format data / factory reset**。
2. 返回主菜单 → **Apply update** → **Apply from ADB**。
3. 主机执行：

```bash
adb -d sideload lineage-22.2-*-nx606j-signed.zip
```

4. 如需要 GApps，在首次启动前继续 sideload（arm64）。
5. 返回 → **Reboot system now**。
6. 首次启动最多约 15 分钟。

---

## 八、刷后验证

- [ ] 通话/短信/移动数据
- [ ] Wi-Fi/蓝牙
- [ ] 相机（前后）
- [ ] 指纹
- [ ] 传感器（重力/距离/光线/指南针）
- [ ] USB OTG
- [ ] 充电/续航
- [ ] 双卡（如使用）

---

## 九、EDL/USB 故障排查

### 现象：`Device detected` 后 bulk timeout

| 可能原因 | 处理 |
|---|---|
| USB 端口/线不稳 | 换主板后置 USB 2.0 口；换确定能传数据的线 |
| loader 不匹配 | 换匹配 SDM845 的 Firehose loader |
| EDL 入口不干净 | 优先硬件组合进 EDL；`adb reboot edl` 仅作备选 |
| 驱动占用 | Linux 下尝试解绑 `qcserial`；Windows 确认无黄色感叹号 |
| EDL 工具兼容性 | 换 bkerler/edl 版本，或 Windows QFIL |

### 现象：Fastboot 能看到设备但命令不支持

- 原厂 ABL 只支持很少命令；不要反复试 `flash/unlock`。
- 先确认是否已按官方流程写入自定义 ABL。
- 仍不行：停止，改用 QFIL/官方线刷恢复。

### 现象：完全无枚举

- 设备管理器/Linux `lsusb` 都看不到 9008 或 fastboot。
- 先修线/端口/驱动/进入模式；**不要写入**。

---

## 十、救砖（官方线刷）

适用：写错 ABL、系统起不来、只能进 EDL。

1. 进入纯净 EDL 9008。
2. 用上次成功的官方固件包 + QFIL + 驱动。
3. 执行官方全量线刷，重写 `abl`、`boot`、`system` 等。
4. 恢复到出厂状态后，先测试通话/短信/数据/Wi-Fi，再决定是否继续。

> 上次就是靠官方线刷恢复的；这套包和驱动必须保留。

---

## 十一、备份建议

解锁前至少备份用户数据（照片/文件/联系人）。  
分区级备份（`abl/boot/recovery/modem/persist/efs`）需要 root 或 EDL 读取；当前官方系统未 root，先不做。

已有：

- 原厂 ABL：`~/nubia-recovery/abl-stock.elf`
- 官方系统已恢复，可正常使用

---

## 十二、执行清单

- [ ] 备份数据
- [ ] 确认官方系统功能正常
- [ ] 准备并校验 ABL / ROM / Recovery / Loader / 救砖包
- [ ] 进入 EDL，`printgpt` 稳定
- [ ] 写 ABL
- [ ] 解锁（`NUBIA_NX616J`）
- [ ] 刷 Recovery
- [ ] Format data
- [ ] Sideload LineageOS
- [ ] 首次启动并逐项验证

---

## 十三、最终建议

- **稳定主力机**：停留在已恢复的官方系统。
- **要现代 Android/安全补丁**：LineageOS 是现实选择，但最高危仍是 EDL 写 ABL。
- **要桌面 Linux**：Z18 目前没有成熟日常方案，不建议。

> 记住：**通信不稳不写，文件不校验不写，救砖包不在手边不刷。**
