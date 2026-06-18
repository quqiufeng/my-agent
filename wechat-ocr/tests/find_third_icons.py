#!/usr/bin/env python3
"""WeChat OCR - 第三列小图标检测
只扫描第三列区域（时间戳+40px分界），找小方形暗色块
用法: python3 find_third_icons.py <第三列X> <窗口X> <窗口Y> <窗口W> <窗口H>
"""
import cv2, numpy as np, mss, os, sys
from PIL import Image, ImageDraw, ImageFont

col3_x = int(sys.argv[1])
wx = int(sys.argv[2]); wy = int(sys.argv[3])
ww = int(sys.argv[4]); wh = int(sys.argv[5])

with mss.mss() as sct:
    img = np.array(sct.grab({"left":wx,"top":wy,"width":ww,"height":wh}))

gray = cv2.cvtColor(img, cv2.COLOR_RGBA2GRAY)

# 只扫第三列
roi = gray[10:wh-10, col3_x-wx:ww-wx-10]

all_blobs = []
for thr in range(180, 60, -20):
    _, t = cv2.threshold(roi, thr, 255, cv2.THRESH_BINARY_INV)
    cs, _ = cv2.findContours(t, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for c in cs:
        x, y, w, h = cv2.boundingRect(c)
        ratio = w / h if h > 0 else 0
        if h < 14 or w < 12: continue
        if ratio > 1.8 or ratio < 0.5: continue
        if w*h < 150 or w*h > 3000: continue
        all_blobs.append((col3_x+x, 10+y, w, h, thr))

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

draw.line([(col3_x-wx,0),(col3_x-wx,wh)], fill=(255,0,0), width=2)
draw.text((10, 10), f"第三列 {len(blobs)} 个小图标", fill=(0,255,0), font=font or ImageFont.load_default())

for i, (bx, by, bw, bh) in enumerate(blobs):
    draw.rectangle([(bx-wx,by),(bx-wx+bw,by+bh)], outline=(0,255,0), width=1)
    draw.text((bx-wx, by-10), str(i+1), fill=(0,255,0), font=font or ImageFont.load_default())

out = os.path.expanduser("~/wechat_third_icons.png")
cv2.imwrite(out, cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR))
print(f"标记图: {out}\n第三列找到 {len(blobs)} 个小图标")
