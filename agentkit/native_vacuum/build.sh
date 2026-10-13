#!/usr/bin/env bash
# build.sh — 编译科沃斯原生内核 vacuum（C，libcurl+openssl+cJSON）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
gcc -O2 -w -o "$HERE/vacuum" "$HERE/vacuum_core.c" -lcurl -lcrypto -lcjson
echo "built: $HERE/vacuum"
