#!/usr/bin/env python3
"""把任意图片居中裁成 824x1200，转成设备锁屏用的 8 位灰度原始数据。
用法: make_lock.py <原图> [输出=lock.gray]
部署: scp -O lock.gray kindle:/mnt/us/ui/lock.gray
"""
import sys
from PIL import Image

W, H = 824, 1200
src = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else "lock.gray"
im = Image.open(src).convert("RGB")
tw = round(im.height * W / H)
if tw <= im.width:
    x0 = (im.width - tw) // 2
    box = (x0, 0, x0 + tw, im.height)
else:
    th = round(im.width * H / W)
    y0 = (im.height - th) // 2
    box = (0, y0, im.width, y0 + th)
g = im.crop(box).resize((W, H), Image.LANCZOS).convert("L")
open(out, "wb").write(g.tobytes())
g.save(out + ".prev.png")
print(f"{src} -> {out} ({len(g.tobytes())} bytes, 824x1200 gray)")
