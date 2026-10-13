#!/bin/bash
# static_build.sh — StaticPy 增量编译 + 单文件 ELF 生成
set -euo pipefail

# Chez Scheme 路径可通过环境变量覆盖，默认使用 /opt/ChezScheme/ta6le
SCHEME_DIR="${CHEZ_SCHEME_DIR:-/opt/ChezScheme/ta6le}"
SCHEME="${CHEZ_SCHEME:-$SCHEME_DIR/bin/ta6le/scheme}"
SCHEME_BOOT_DIR="${CHEZ_BOOT_DIR:-/opt/ChezScheme/boot/ta6le}"
RESCHEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="/tmp/staticpy-cache"

if [ $# -lt 1 ]; then
    echo "Usage: $0 input.py [output-name]"
    echo "Environment variables:"
    echo "  CHEZ_SCHEME_DIR  - Chez Scheme install dir (default: /opt/ChezScheme/ta6le)"
    echo "  CHEZ_SCHEME      - Scheme executable (default: \$CHEZ_SCHEME_DIR/bin/ta6le/scheme)"
    echo "  CHEZ_BOOT_DIR    - Boot files dir (default: /opt/ChezScheme/boot/ta6le)"
    exit 1
fi

if [ ! -x "$SCHEME" ]; then
    echo "Error: Chez Scheme not found at $SCHEME"
    echo "Set CHEZ_SCHEME_DIR or CHEZ_SCHEME environment variable."
    exit 1
fi

INPUT="$1"
STEM="${2:-$(basename "$INPUT" .py)}"
FFI_SCM="${3:-}"
mkdir -p "$CACHE_DIR"
cd "$RESCHEME_DIR"

echo "=== StaticPy Build ==="
echo "Source: $INPUT"
echo "Output: $STEM"
echo "Chez:   $SCHEME"

# Detect whether input is already Scheme code
INPUT_EXT="${INPUT##*.}"
IS_SCM=0
if [ "$INPUT_EXT" = "scm" ] || [ "$INPUT_EXT" = "ss" ]; then
    IS_SCM=1
fi

# Step 1: Translate (skip for .scm/.ss inputs)
echo ">>> Step 1: Translate"
if [ "$IS_SCM" = "1" ]; then
    echo "  -> Input is Scheme code, skipping Python translation"
    cp "$INPUT" "$CACHE_DIR/${STEM}_code.ss"
else
    if [ "${STATICPY_WARN:-0}" = "1" ]; then
        /data/venv/bin/python3 static_translate.py --warn "$INPUT" > "$CACHE_DIR/${STEM}_code.ss"
    else
        /data/venv/bin/python3 static_translate.py "$INPUT" > "$CACHE_DIR/${STEM}_code.ss"
    fi
fi

# Step 2: Compute content hash for caching
if [ "$IS_SCM" = "1" ]; then
    if [ -n "$FFI_SCM" ]; then
        PRELUDE_HASH=$(md5sum static_prelude.scm static_stdlib.scm "$FFI_SCM" "$CACHE_DIR/${STEM}_code.ss" 2>/dev/null | md5sum | cut -d' ' -f1)
    else
        PRELUDE_HASH=$(md5sum static_prelude.scm static_stdlib.scm "$CACHE_DIR/${STEM}_code.ss" 2>/dev/null | md5sum | cut -d' ' -f1)
    fi
else
    if [ -n "$FFI_SCM" ]; then
        PRELUDE_HASH=$(md5sum static_prelude.scm static_stdlib.scm "$FFI_SCM" static_translate.py "$CACHE_DIR/${STEM}_code.ss" 2>/dev/null | md5sum | cut -d' ' -f1)
    else
        PRELUDE_HASH=$(md5sum static_prelude.scm static_stdlib.scm static_translate.py "$CACHE_DIR/${STEM}_code.ss" 2>/dev/null | md5sum | cut -d' ' -f1)
    fi
fi
CACHED_SO="$CACHE_DIR/${STEM}_${PRELUDE_HASH}.so"
CACHED_ELF="$CACHE_DIR/${STEM}_${PRELUDE_HASH}"

if [ -f "$CACHED_ELF" ] && [ -f "$CACHED_SO" ]; then
    echo ">>> Step 2: Cached, skip compile"
    OUTPUT_SO="$CACHED_SO"
    OUTPUT_ELF="$CACHED_ELF"
else
    echo ">>> Step 2: Compile"
    # Merge prelude + stdlib + optional ffi + user code
    MERGED_SS="$CACHE_DIR/${STEM}_${PRELUDE_HASH}.ss"
    cat static_prelude.scm > "$MERGED_SS"
    echo "" >> "$MERGED_SS"
    cat static_stdlib.scm >> "$MERGED_SS"
    echo "" >> "$MERGED_SS"
    if [ -n "$FFI_SCM" ] && [ -f "$FFI_SCM" ]; then
        cat "$FFI_SCM" >> "$MERGED_SS"
        echo "" >> "$MERGED_SS"
    fi
    cat "$CACHE_DIR/${STEM}_code.ss" >> "$MERGED_SS"
    
    cat > "$CACHE_DIR/compile_${PRELUDE_HASH}.ss" << EOF
(import (chezscheme))
(compile-file "$MERGED_SS")
EOF
    $SCHEME --quiet "$CACHE_DIR/compile_${PRELUDE_HASH}.ss" 2>&1
    mv "${MERGED_SS}.so" "$CACHED_SO" 2>/dev/null || true

    # Step 3: Build standalone ELF binary
    echo ">>> Step 3: Build standalone ELF binary"
    BUILD_DIR="$CACHE_DIR/elf_${PRELUDE_HASH}"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # Embed Chez boot files as linkable objects
    cp "$SCHEME_BOOT_DIR/petite.boot" "$BUILD_DIR/petite.boot"
    cp "$SCHEME_BOOT_DIR/scheme.boot" "$BUILD_DIR/scheme.boot"
    (cd "$BUILD_DIR" && \
      objcopy --input-target binary --output-target elf64-x86-64 --binary-architecture i386:x86-64 \
        petite.boot petite_boot.o && \
      objcopy --input-target binary --output-target elf64-x86-64 --binary-architecture i386:x86-64 \
        scheme.boot scheme_boot.o && \
      objcopy --add-section .note.GNU-stack=/dev/null --set-section-flags .note.GNU-stack=readonly \
        petite_boot.o petite_boot.o && \
      objcopy --add-section .note.GNU-stack=/dev/null --set-section-flags .note.GNU-stack=readonly \
        scheme_boot.o scheme_boot.o)

    # Write C launcher
    cat > "$BUILD_DIR/launcher.c" << 'CCODE'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "scheme.h"

extern char _binary_petite_boot_start[];
extern char _binary_petite_boot_end[];
extern char _binary_scheme_boot_start[];
extern char _binary_scheme_boot_end[];

int main(int argc, char **argv) {
    Sscheme_init(NULL);
    Sregister_boot_file_bytes("petite.boot",
        _binary_petite_boot_start,
        _binary_petite_boot_end - _binary_petite_boot_start);
    Sregister_boot_file_bytes("scheme.boot",
        _binary_scheme_boot_start,
        _binary_scheme_boot_end - _binary_scheme_boot_start);
    Sbuild_heap(NULL, NULL);

    char *prog_path = "CSTEM.so";
    char self_path[2048];
    if (argc >= 1 && argv[0]) {
        char *slash = strrchr(argv[0], '/');
        if (slash) {
            size_t dir_len = slash - argv[0] + 1;
            if (dir_len < sizeof(self_path)) {
                memcpy(self_path, argv[0], dir_len);
                self_path[dir_len] = '\0';
                strncat(self_path, "CSTEM.so", sizeof(self_path) - dir_len - 1);
                prog_path = self_path;
            }
        }
    }

    return Sscheme_program(prog_path, argc, (const char **)argv);
}
CCODE
    # CSTEM 只包含文件名（不包含目录路径），避免路径重复
    CSTEM_BASE="$(basename "$STEM")"
    sed "s|CSTEM|$CSTEM_BASE|g" "$BUILD_DIR/launcher.c" > "$BUILD_DIR/launcher_fixed.c"

    gcc -o "$CACHED_ELF" \
        "$BUILD_DIR/launcher_fixed.c" \
        "$BUILD_DIR/petite_boot.o" \
        "$BUILD_DIR/scheme_boot.o" \
        -I"$SCHEME_DIR/boot/ta6le" \
        -L"$SCHEME_DIR/boot/ta6le" \
        -l:libkernel.a \
        "$SCHEME_DIR/lz4/lib/liblz4.a" \
        "$SCHEME_DIR/zlib/libz.a" \
        -ldl -lpthread -lm -ltinfo \
        -L/data/venv/lib/python3.12/site-packages/torch/lib \
        -Wl,--no-as-needed -lc10 -ltorch_cpu -ltorch -Wl,--as-needed \
        -Wl,-rpath,/data/venv/lib/python3.12/site-packages/torch/lib \
        2>&1

    echo "  -> ELF cached"
    OUTPUT_SO="$CACHED_SO"
    OUTPUT_ELF="$CACHED_ELF"
fi

# Step 4: Create output directory with symlinks
OUT_DIR="/tmp/static-build-$$"
mkdir -p "$OUT_DIR"
# 创建 STEM 的子目录（如果 STEM 包含斜杠）
mkdir -p "$OUT_DIR/$(dirname "$STEM")"
ln -sf "$OUTPUT_SO" "$OUT_DIR/$STEM.so"
ln -sf "$OUTPUT_ELF" "$OUT_DIR/$STEM"

# Copy final outputs to workspace
cp -L "$OUTPUT_SO" "$RESCHEME_DIR/$STEM.so" 2>/dev/null || true
cp -L "$OUTPUT_ELF" "$RESCHEME_DIR/$STEM" 2>/dev/null || true

TORCH_LIB_PATH=$(/data/venv/bin/python3 -c "import torch; import os; print(os.path.dirname(torch.__file__)+'/lib')" 2>/dev/null || echo "")

echo "=== Build complete ==="
echo "Output:"
echo "  $RESCHEME_DIR/$STEM       (ELF binary, standalone)"
echo "  $RESCHEME_DIR/$STEM.so    (Chez AOT compiled Scheme)"
echo "Run:"
echo "  ./$STEM"
echo "Note: If your code uses torch/openblas/cuda, ensure LD_LIBRARY_PATH includes the required .so directories."
if [ -n "$TORCH_LIB_PATH" ]; then
    echo "  Example: LD_LIBRARY_PATH=$TORCH_LIB_PATH:\$LD_LIBRARY_PATH ./$STEM"
fi
