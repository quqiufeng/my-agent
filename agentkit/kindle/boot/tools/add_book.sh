#!/bin/bash
# 电子书 → Kindle：主机解析(mobi/azw/azw3/epub/pdf) → 拼纯文本 → 推到设备
# 用法: add_book.sh <书文件> [设备上的文件名]
#       例: add_book.sh ~/book.azw3 "我的书.azw3"
set -uo pipefail
SRC="${1:?用法: add_book.sh <书文件> [设备文件名]}"
[ -f "$SRC" ] || { echo "找不到: $SRC" >&2; exit 1; }
NAME="${2:-$(basename "$SRC")}"
K="${KINDLE_HOST:-kindle}"
W=/tmp/kindle_book_import
rm -rf "$W"; mkdir -p "$W"

( cd /opt/my_db && LD_LIBRARY_PATH=/opt/my_db ./tools/import_book /tmp/cache "$SRC" /books/_import "$W" --skip-vectors >/dev/null ) \
  || { echo "解析失败: $SRC" >&2; exit 1; }

python3 - "$W/_import/chapters" "$W/$NAME.txt" <<'PY'
import os, re, sys
d, out = sys.argv[1], sys.argv[2]
dirs = [x for x in os.listdir(d) if os.path.isdir(os.path.join(d, x))]
def key(n):
    m = re.match(r'(\d+)-', n)
    return (int(m.group(1)) if m else 10**9, n)
lines = []
for n in sorted(dirs, key=key):
    lines.append('## ' + re.sub(r'^\d+-', '', n))
    pdir = os.path.join(d, n)
    for p in sorted(os.listdir(pdir)):
        if not p.endswith('.md'):
            continue
        with open(os.path.join(pdir, p), encoding='utf-8', errors='replace') as f:
            for ln in f.read().replace('\r', '').split('\n'):
                if ln.strip():
                    lines.append(ln.rstrip())
    lines.append('')
open(out, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
print(f"文本: {out} ({len(lines)} 行)")
PY

scp -O -q "$SRC" "$K:/mnt/us/documents/$NAME" || exit 1
scp -O -q "$W/$NAME.txt" "$K:/mnt/us/ui/books/$NAME.txt" || exit 1
ssh -o BatchMode=yes "$K" "ls -l '/mnt/us/documents/$NAME' '/mnt/us/ui/books/$NAME.txt'"
