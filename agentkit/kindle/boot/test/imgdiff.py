#!/usr/bin/env python3
"""UI 视觉回归：比较两张 824x1200 灰度帧。
用法: imgdiff.py a.png b.png [阈值=0.02]
退出码 0=通过, 1=差异超阈值。"""
import sys
import numpy as np
from PIL import Image

if len(sys.argv) < 3:
    print(__doc__)
    sys.exit(2)
a = np.asarray(Image.open(sys.argv[1]).convert("L"), dtype=np.int16)
b = np.asarray(Image.open(sys.argv[2]).convert("L"), dtype=np.int16)
if a.shape != b.shape:
    print(f"尺寸不同: {a.shape} vs {b.shape}")
    sys.exit(1)
tol = float(sys.argv[3]) if len(sys.argv) > 3 else 0.02
ratio = (np.abs(a - b) > 32).mean()
print(f"差异像素比例 {ratio:.4f} (阈值 {tol})")
sys.exit(0 if ratio <= tol else 1)
