# 锁屏图（顶部 lock 开关）

拨动顶部 lock 开关 → 驱动锁住 keypad/fiveway/accelerometer → lvgui 轮询 `/proc/keypad`
→ 回调 Lua `on_lock()` → 显示 `/mnt/us/ui/lock.gray`；解锁后恢复原界面。

`lock.gray` 是 **824×1200 的 8 位灰度原始数据**（恰好 988800 字节，**没有文件头**）。
当前默认图由 `big_2048.png` 生成（预览见 `lock.gray.prev.png`）。

---

## 换图（三步）

```bash
# 1) 任意图片 → 居中裁剪/缩放/灰度，产出 lock.gray（同目录还会生成 lock.gray.prev.png 预览）
python3 /opt/my-agent/agentkit/kindle/boot/lock/make_lock.py ~/图片.png

# 2) 推到设备
scp -O /opt/my-agent/agentkit/kindle/boot/lock/lock.gray kindle:/mnt/us/ui/lock.gray

# 3) 测试（锁屏/解锁/抓图确认）
cd /opt/my-agent/agentkit/kindle/boot/test
./kui lock on          # 模拟拨到 lock
./kui shot /tmp/lock.png
./kui lock off         # 解锁，应恢复原阅读页
```

也可以一条命令直接生成并部署：

```bash
python3 boot/lock/make_lock.py ~/图片.png /tmp/lock.gray \
  && scp -O /tmp/lock.gray kindle:/mnt/us/ui/lock.gray
```

---

## 裁剪规则

- 目标比例 **824:1200（0.6867）**，居中裁剪：宽图裁左右，高图裁上下。
- 再按 LANCZOS 缩放到 824×1200，转 8 位灰度。
- 原图建议 ≥ 824×1200 且主体居中（人像/风景都行）。

## 注意事项

1. 文件必须**恰好** `824*1200 = 988800` 字节，否则 `ui.overlay()` 返回 false，
   锁屏会**自动回退为文字**「已锁定 / 拨动顶部 lock 开关解锁」。
2. 想换回文字锁屏：把设备上的 `/mnt/us/ui/lock.gray` 改名或删除即可（无需改代码）。
3. 锁屏图在设备上直接替换即可生效（下次锁定自动读取），**不用重启 lvgui**。
4. 建议把换下来的图保留在本目录（如 `lock.bak.gray`）方便回滚。
