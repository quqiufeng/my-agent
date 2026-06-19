#!/usr/bin/env python3
"""WeChat OCR - 第一列小图标检测
只扫描第一列（图标列，固定约 80px 宽），找方形暗色块
用法: python3 find_first_icons.py <窗口X> <窗口Y> <窗口W> <窗口H> [输出路径]
"""
import cv2, numpy as np, os, sys, mss
from PIL import Image, ImageDraw, ImageFont

wx = int(sys.argv[1]); wy = int(sys.argv[2])
ww = int(sys.argv[3]); wh = int(sys.argv[4])
out = sys.argv[5] if len(sys.argv) > 5 else os.path.expanduser("~/wechat_first_icons.png")

COL1_W = 75  # 第一列固定宽度

# 截图
with mss.mss() as sct:
    img = np.array(sct.grab({"left":wx,"top":wy,"width":ww,"height":wh}))

# 只取第一列区域
roi = img[10:wh-10, 5:COL1_W]
gray = cv2.cvtColor(roi, cv2.COLOR_RGBA2GRAY)

# ---- 多阈值找图标 ----
all_blobs = []
for thr in range(180, 5, -5):
    _, t = cv2.threshold(gray, thr, 255, cv2.THRESH_BINARY_INV)
    cs, _ = cv2.findContours(t, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for c in cs:
        x, y, w, h = cv2.boundingRect(c)
        ratio = w / h if h > 0 else 0
        if h < 6 or w < 6: continue
        if ratio > 2.2 or ratio < 0.35: continue
        if w*h < 36 or w*h > 3000: continue
        all_blobs.append((5 + x, 10 + y, w, h, 5 + x + w//2, 10 + y + h//2))

# 去重
unique = {}
for bx, by, bw, bh, cx, cy in all_blobs:
    key = (cx//6, cy//6)
    if key not in unique:
        unique[key] = (bx, by, bw, bh, cx, cy)

blob_list = sorted(unique.values(), key=lambda b: (b[1], b[0]))

# ---- 文字行过滤 ----
TEXT_ROW_Y_TOLERANCE = 15
TEXT_ROW_X_MAX = 45
TEXT_ROW_MIN_NEIGHBORS = 4

is_text = [False] * len(blob_list)
for i, (bx1, by1, bw1, bh1, cx1, cy1) in enumerate(blob_list):
    if is_text[i]: continue
    neighbors = []
    for j, (bx2, by2, bw2, bh2, cx2, cy2) in enumerate(blob_list):
        if i == j or is_text[j]: continue
        if abs(cy2 - cy1) <= TEXT_ROW_Y_TOLERANCE and abs(cx2 - cx1) <= TEXT_ROW_X_MAX:
            neighbors.append(j)
    if len(neighbors) >= TEXT_ROW_MIN_NEIGHBORS:
        is_text[i] = True
        for j in neighbors: is_text[j] = True

blobs = [(bx, by, bw, bh) for i, (bx, by, bw, bh, cx, cy) in enumerate(blob_list) if not is_text[i]]
blobs = sorted(blobs, key=lambda b: (b[1], b[0]))

# ---- 标注 ----
pil_img = Image.fromarray(cv2.cvtColor(img, cv2.COLOR_RGBA2RGB))
draw = ImageDraw.Draw(pil_img)
font = None
for fp in ["/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
           "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
           "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"]:
    if os.path.exists(fp):
        font = ImageFont.truetype(fp, 14)
        break

# 第一列范围标注
draw.line([(COL1_W, 0), (COL1_W, wh)], fill=(0, 0, 255), width=2)
draw.text((10, 10), f"第一列 {len(blobs)} 个小图标", fill=(0,255,0), font=font or ImageFont.load_default())

for i, (bx, by, bw, bh) in enumerate(blobs):
    draw.rectangle([(bx, by), (bx+bw, by+bh)], outline=(0, 255, 0), width=1)
    draw.text((bx, by-10), str(i+1), fill=(0, 255, 0), font=font or ImageFont.load_default())

cv2.imwrite(out, cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR))
print(f"标记图: {out}\n第一列找到 {len(blobs)} 个小图标")
