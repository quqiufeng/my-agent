#!/usr/bin/env python3
"""WeChat OCR - 第三列小图标检测
用法: python3 find_icons.py <第三列起始X> <窗口X> <窗口Y> <窗口W> <窗口H>
功能: 截图 → 第三列底部找小图标 → 标注 → 保存
"""
import cv2, numpy as np, subprocess, re, mss, os, sys
from PIL import Image, ImageDraw, ImageFont

col3_x = int(sys.argv[1])
wx = int(sys.argv[2])
wy = int(sys.argv[3])
ww = int(sys.argv[4])
wh = int(sys.argv[5])

with mss.mss() as sct:
    img = np.array(sct.grab({"left":wx,"top":wy,"width":ww,"height":wh}))

gray = cv2.cvtColor(img, cv2.COLOR_RGBA2GRAY)

# 第三列全部区域
roi = gray[20:wh-20, col3_x-wx:]
_, thresh = cv2.threshold(roi, 200, 255, cv2.THRESH_BINARY_INV)
contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

# 过滤出方形小块
blobs = []
for c in contours:
    x, y, w, h = cv2.boundingRect(c)
    area = w * h
    ratio = w / h if h > 0 else 0
    if 60 < area < 5000 and h > 8 and 0.4 < ratio < 2.5:
        blobs.append((col3_x+x, 20+y, w, h))

# 按Y分组
rows = {}
for x, y, w, h in blobs:
    key = round(y, -1)
    if key not in rows: rows[key] = []
    rows[key].append((x, y, w, h))

# 找到有4-8个成员的组
vis = cv2.cvtColor(img, cv2.COLOR_RGBA2BGR)
pil_img = Image.fromarray(cv2.cvtColor(vis, cv2.COLOR_BGR2RGB))
draw = ImageDraw.Draw(pil_img)

# 字体
font_paths = ["/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
              "/usr/share/fonts/opencore/noto/NotoSansCJK-Regular.ttc",
              "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
font = None
for fp in font_paths:
    if os.path.exists(fp):
        font = ImageFont.truetype(fp, 18)
        break
if font is None:
    font = ImageFont.load_default()

# 画分界线
draw.line([(col3_x-wx,0),(col3_x-wx,wh)], fill=(255,0,0), width=2)

found = False
for y_key in sorted(rows.keys()):
    g = rows[y_key]
    g.sort(key=lambda i: i[0])
    if 4 <= len(g) <= 8:
        gaps = [g[i+1][0]-g[i][0] for i in range(len(g)-1)]
        avg_gap = np.mean(gaps) if gaps else 0
        if 30 < avg_gap < 80:
            found = True
            draw.text((10, y_key-wy-20), f"y={y_key} {len(g)}个 间距{avg_gap:.0f}px", fill=(0,255,0), font=font)
            for i, (x, y, w, h) in enumerate(g):
                color = (0,255,0) if i == 2 else (255,255,0)
                draw.rectangle([(x-wx,y-wy),(x-wx+w,y-wy+h)], outline=color, width=2)
                draw.text((x-wx, y-wy-14), str(i+1), fill=color, font=font)
                if i == 2:
                    draw.text((x-wx, y-wy+h+2), "📎文件", fill=(0,0,255), font=font)

if not found:
    draw.text((10, 10), "未找到5~8个等距图标的行", fill=(255,0,0), font=font)
    # 标出所有blob
    for x, y, w, h in blobs:
        draw.rectangle([(x-wx,y-wy),(x-wx+w,y-wy+h)], outline=(0,255,0), width=1)

out = os.path.expanduser("~/wechat_icons_test.png")
vis = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
cv2.imwrite(out, vis)
print(f"标记图: {out}")
if found:
    print("✅ 找到图标行")
else:
    print(f"❌ 未找到图标行 (共{len(blobs)}个候选)")
