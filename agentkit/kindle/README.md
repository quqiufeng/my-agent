# Kindle DXG 自研电子墨水 UI（agentkit/kindle）

LVGL(C) + 内嵌 LuaJIT + FreeType 的电子墨水 UI：**书架 + 阅读器**，agent 可脚本驱动（FIFO 通道）。
完整背景与踩坑见 `/opt/my-agent/kindleDGX.md`（§14 显示/刷新、§16 阅读器）。

## 文件
- `lvgui.c`     — 单体 app：LVGL 渲染 + 内嵌 LuaJIT + 控制 FIFO(`/tmp/ui.cmd`) + FreeType 加载 TTF；显示走「灰度缓冲 → PNG → /usr/sbin/eips」
- `app.lua`     — 书架 + 阅读器两屏（常驻控件 + show/hide，稳定重绘）
- `lv_conf.h`   — LVGL 配置（`LV_USE_FREETYPE=1`；montserrat 14/24/32/48）
- `start.sh`    — 停 cvm + 设横竖屏 + 常驻运行 lvgui
- `open.sh`     — 打开书：交接给 kindlepdfviewer（可选方案）
- `hello_main.c`— 最小 LVGL→e-ink 示例

## Lua API（C 暴露给 agent）
`ui.clear/title/label/text/set/pos/size/align/color/log/button/list/style/hr/show` + `ui.ALIGN_*`
按键回调：`on_key(name)`（up/down/left/right/enter/home/back/menu）

## 编译（armv6 musl 静态；需先交叉编 LuaJIT + FreeType）
```bash
CC=~/opt/arm-linux-musleabi-cross/bin/arm-linux-musleabi-gcc
$CC -O2 -march=armv6 -mfloat-abi=softfp -mfpu=vfp -marm -DLV_CONF_INCLUDE_SIMPLE \
  -Ilvgl -Ilvgl/src -I. -Iluajit/src -Ift-out/include/freetype2 \
  $(find lvgl/src -name '*.c') lvgui.c luajit/src/libluajit.a ft-out/lib/libfreetype.a \
  -o lvgui -static -lm
```
（依赖：LVGL 8.3 源码、LuaJIT 2.1(musl)、FreeType 2.13(musl)、文泉驿/仓耳今楷 TTF。）

## 部署（设备 `/mnt/us/`）
```
lvgui · ui/{init.lua,font.ttf,books/<书名>.txt,start.sh,open.sh}
```

## 解析电子书（复用 my_db）
```bash
cd /opt/my_db
LD_LIBRARY_PATH=/opt/my_db ./tools/import_book /tmp/cache ~/book.mobi /books/书名 /opt/books --skip-vectors
# 拼成纯文本 → /mnt/us/ui/books/<书名>.txt
```
