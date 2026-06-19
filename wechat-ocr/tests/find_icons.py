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

# 多阈值合并（从深色到浅色全覆盖）
all_blobs = []
for thr in range(180, 20, -10):
    _, t = cv2.threshold(roi, thr, 255, cv2.THRESH_BINARY_INV)
    cs, _ = cv2.findContours(t, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for c in cs:
        x, y, w, h = cv2.boundingRect(c)
        ratio = w / h if h > 0 else 0
        if h < 8 or w < 8: continue         # 过滤微小碎片
        if ratio > 2.0 or ratio < 0.4: continue  # 图标近似方形
        if w*h < 60 or w*h > 4000: continue  # 放宽面积范围
        all_blobs.append((10+x, 10+y, w, h, 10+x+w//2, 10+y+h//2))

# 去重
unique = {}
for bx, by, bw, bh, cx, cy in all_blobs:
    key = (cx//8, cy//8)
    if key not in unique:
        unique[key] = (bx, by, bw, bh, cx, cy)

blob_list = sorted(unique.values(), key=lambda b: (b[1], b[0]))

# --- 按行排列过滤文字 ---
# 文字特征是多个blob在同一水平线上等距排列。
# 对每个blob，统计其±15px高度范围内、水平间距<150px的邻居数。
# 邻居≥3的视为文字行，整行排除。
TEXT_ROW_Y_TOLERANCE = 15
TEXT_ROW_X_MAX = 60   # 文字间距密（<60px），图标间距疏（>60px）
TEXT_ROW_MIN_NEIGHBORS = 3

# 对每个blob，找同一水平线上间距<60px的邻居
# 如果3+个blob密集排列，判定为文字行
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

# 只保留非文字 blob
blobs = [(bx, by, bw, bh) for i, (bx, by, bw, bh, cx, cy) in enumerate(blob_list) if not is_text[i]]
blobs = sorted(blobs, key=lambda b: (b[1], b[0]))

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
