#!/bin/sh
# 交叉编译 Kindle DXG 的 lvgui（armv6 / musl / 静态）。
# 依赖源码树默认在 /opt/kindle-deps（可用变量覆盖）：
#   LVGL_SRC   LVGL 8.3.11 源码目录
#   LUAJIT_DIR LuaJIT 2.1 交叉编译目录（含 src/libluajit.a）
#   FT_OUT     FreeType 交叉安装目录（含 include/freetype2 与 lib/libfreetype.a）
# 用法：sh build.sh       或  LVGL_SRC=... LUAJIT_DIR=... FT_OUT=... sh build.sh
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
CC=${CROSS_CC:-$HOME/opt/arm-linux-musleabi-cross/bin/arm-linux-musleabi-gcc}
LVGL_SRC=${LVGL_SRC:-/opt/kindle-deps/lvgl}
LUAJIT_DIR=${LUAJIT_DIR:-/opt/kindle-deps/luajit}
FT_OUT=${FT_OUT:-/opt/kindle-deps/ft-out}
cd "$DIR"
$CC -O2 -march=armv6 -mfloat-abi=softfp -mfpu=vfp -marm -DLV_CONF_INCLUDE_SIMPLE \
  -I"$LVGL_SRC" -I"$LVGL_SRC/src" -I. -I"$LUAJIT_DIR/src" -I"$FT_OUT/include/freetype2" \
  $(find "$LVGL_SRC/src" -name '*.c') lvgui.c "$LUAJIT_DIR/src/libluajit.a" "$FT_OUT/lib/libfreetype.a" \
  -o lvgui -static -lm
echo "built: $DIR/lvgui"
