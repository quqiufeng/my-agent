# Kindle DXG 自研电子墨水 UI（agentkit/kindle）

LVGL(C) + 内嵌 LuaJIT + FreeType 的电子墨水 UI：**书架 + 阅读器**，agent 可脚本驱动（FIFO `/tmp/ui.cmd`）。
完整背景与踩坑见 `/opt/my-agent/kindleDGX.md`（§14 显示/刷新、§16 阅读器）。

## 目录

```
kindle/
├── boot/
│   ├── src/     # 交叉编译相关：C 源码 / 配置 / 构建&启动脚本 / 产物
│   │   ├── lvgui.c      单体 app：LVGL 渲染 + 内嵌 LuaJIT + 控制 FIFO + FreeType
│   │   ├── lv_conf.h    LVGL 配置（LV_USE_FREETYPE=1）
│   │   ├── build.sh     交叉编译脚本（依赖默认 /opt/kindle-deps）
│   │   ├── start.sh     设备端：停 cvm + 设竖屏 + 常驻运行 lvgui
│   │   ├── open.sh      打开书：交接给 kindlepdfviewer（可选）
│   │   ├── lvgui        当前构建产物（scp 到设备 /mnt/us/lvgui）
│   │   └── lvgui.prev   上一版产物（回滚用）
│   ├── lua/     # 应用层（界面/互动逻辑，改这里最常动）
│   │   ├── init.lua     书架 + 阅读器（当前版本）
│   │   ├── app.lua      早期版本（on_key 版）
│   │   └── README.md    Lua 开发指南（API/按键/排版/自动化测试）
│   ├── lock/    # 锁屏图：lock.gray(824x1200 灰度) + make_lock.py + README(换图方法)
│   └── test/    # agent 自动化测试（模拟人手动操作）
│       ├── kui          CLI：state/tap/say/dump/shot/run/restart
│       ├── smoke.lua    冒烟测试（结果写 events 的 PASS/FAIL）
│       ├── imgdiff.py   截图视觉回归对比
│       └── README.md    全自动测试 + AI 闭环修复流程
└── README.md

/opt/kindle-deps/          # 依赖源码树（第三方，不入本仓）
├── lvgl/                  # LVGL 8.3.11 源码（lvgl.tar.gz 为原始包）
├── luajit/                # LuaJIT 2.1，交叉编译（src/libluajit.a）
├── freetype/              # FreeType 2.13.3 源码
└── ft-out/                # FreeType 交叉安装（include/freetype2 + lib/libfreetype.a）
```

## Lua API（C 暴露）
`ui.clear/title/label/text/set/pos/size/align/color/log/button/list/style/hr/show`
+ `ui.font(size)`（返回字体句柄）/ `setfont(obj,size)` / `measure(text,size)`→宽,高 / `zoom(obj,z)`
+ `ui.ALIGN_*`
按键回调：优先 `on_code(rawcode)`（原始扫描码）；无 `on_code` 时回退 `on_key(name)`
（name: up/down/left/right/enter/home/back/menu）

**Lua 功能开发指南：[`boot/lua/README.md`](boot/lua/README.md)**（API 详解、按键码、排版分页、调试、完整示例）。

## 编译（armv6 / musl / 静态）
```bash
cd boot/src && sh build.sh        # 产物 ./lvgui
```
依赖默认 `/opt/kindle-deps/{lvgl,luajit,ft-out}`，可用
`LVGL_SRC=… LUAJIT_DIR=… FT_OUT=… CROSS_CC=… sh build.sh` 覆盖。

## 部署（设备 `/mnt/us/`）
```
/mnt/us/lvgui                 ← boot/src/lvgui
/mnt/us/ui/init.lua           ← boot/lua/init.lua
/mnt/us/ui/font.ttf           中文字体（仓耳今楷 / CJK_Bold）
/mnt/us/ui/books/<书名>.txt    拆解后的纯文本（含 "## 章节" 标记）
/mnt/us/ui/pos.lua             阅读进度（运行时生成）
```
重启：`killall lvgui; /sbin/start-stop-daemon -S -b -x /mnt/us/lvgui`
按键解锁：`echo unlock > /proc/keypad; echo unlock > /proc/fiveway`

## 回滚
- 应用层（常用）：`boot/lua/*.lua` 覆盖回 `/mnt/us/ui/` 即回滚，无需重编。
- 内核层：设备 `cp /mnt/us/lvgui.bak /mnt/us/lvgui`；或本仓 `boot/src/lvgui.prev`。

## 解析电子书（复用 my_db）
```bash
cd /opt/my_db
LD_LIBRARY_PATH=/opt/my_db ./tools/import_book /tmp/cache ~/book.mobi /books/书名 /opt/books --skip-vectors
# 拼成纯文本 → /mnt/us/ui/books/<书名>.txt
```
