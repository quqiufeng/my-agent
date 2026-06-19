#!/usr/bin/env python3
"""WeChat OCR - 全窗口小图标检测
扫描整个微信窗口，找出所有小方形暗色块（过滤文字），标注输出
用法: python3 find_icons.py <窗口X> <窗口Y> <窗口W> <窗口H>
"""
import cv2, numpy as np, mss, os, sys
from PIL import Image, ImageDraw, ImageFont

wx = int(sys.argv[1]); wy = int(sys.argv[2])
ww = int(sys.argv[3]); wh = int(sys.argv[4])
out = sys.argv[5] if len(sys.argv) > 5 else os.path.expanduser("~/wechat_icons.png")

with mss.mss() as sct:
    img = np.array(sct.grab({"left":wx,"top":wy,"width":ww,"height":wh}))

gray = cv2.cvtColor(img, cv2.COLOR_RGBA2GRAY)
roi = gray[10:wh-10, 10:ww-10]

# 多阈值合并
all_blobs = []
for thr in range(180, 60, -20):
    _, t = cv2.threshold(roi, thr, 255, cv2.THRESH_BINARY_INV)
    cs, _ = cv2.findContours(t, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for c in cs:
        x, y, w, h = cv2.boundingRect(c)
        ratio = w / h if h > 0 else 0
        if h < 14 or w < 12: continue       # 过滤小文字碎片
        if ratio > 1.6 or ratio < 0.6: continue  # 图标近似方形（比之前更严）
        if w*h < 150 or w*h > 3000: continue

        # --- 文字 vs 图标区分 ---
        # 计算 solidity（轮廓面积 / 凸包面积）
        # 文字（如"公" "消"）有镂空/细笔划，solidity 偏低（<0.65）
        # 图标是实心色块，solidity 偏高（>0.65）
        hull = cv2.convexHull(c)
        hull_area = cv2.contourArea(hull)
        solidity = cv2.contourArea(c) / hull_area if hull_area > 0 else 0
        if solidity < 0.65: continue

        # 计算轮廓的宽高比与面积的综合特征
        # 文字笔划密度高（内部边缘多），图标更均匀
        mask = np.zeros((h, w), dtype=np.uint8)
        cx, cy = x + w//2, y + h//2
        # 在原图中取 ROI
        roi_patch = gray[10+cy-h//2:10+cy+h-h//2, 10+cx-w//2:10+cx+w-w//2]
        if roi_patch.shape[0] < 3 or roi_patch.shape[1] < 3: continue
        # 计算边缘密度（Canny）
        edges = cv2.Canny(roi_patch, 30, 90)
        edge_ratio = np.sum(edges > 0) / (w * h) if w*h > 0 else 1
        if edge_ratio > 0.25: continue  # 文字笔划多，边缘密度高

        all_blobs.append((10+x, 10+y, w, h, thr))

# 去重
unique = {}
for bx, by, bw, bh, bt in all_blobs:
    key = (bx//6, by//6)
    if key not in unique:
        unique[key] = (bx, by, bw, bh)

blobs = sorted(unique.values(), key=lambda b: (b[1], b[0]))

# 标注
pil_img = Image.fromarray(cv2.cvtColor(img, cv2.COLOR_RGBA2RGB))
draw = ImageDraw.Draw(pil_img)
font = None
for fp in ["/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
           "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
           "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"]:
    if os.path.exists(fp):
        font = ImageFont.truetype(fp, 14)
        break

draw.text((10, 10), f"全窗口 {len(blobs)} 个小图标", fill=(0,255,0), font=font or ImageFont.load_default())

for i, (bx, by, bw, bh) in enumerate(blobs):
    draw.rectangle([(bx,by),(bx+bw,by+bh)], outline=(0,255,0), width=1)
    draw.text((bx, by-10), str(i+1), fill=(0,255,0), font=font or ImageFont.load_default())

cv2.imwrite(out, cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR))
print(f"标记图: {out}\n找到 {len(blobs)} 个小图标")
