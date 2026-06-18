#!/usr/bin/env python3
"""WeChat OCR - 三列结构标记图生成
用法: python3 mark_columns.py <第三列起始X坐标>
功能: 截图微信窗口 → 标注三列分界 → 保存到 ~/wechat_3cols_test.png
"""
import cv2, numpy as np, subprocess, re, mss, os, sys
from PIL import Image, ImageDraw, ImageFont

col3 = int(sys.argv[1]) if len(sys.argv) > 1 else 0

geo = subprocess.run(["xdotool","getactivewindow","getwindowgeometry"],
                     capture_output=True,text=True).stdout
wx = int(re.search(r"Position: (\d+)", geo).group(1))
wy = int(re.search(r",(\d+)", geo).group(1))
ww = int(re.search(r"Geometry: (\d+)", geo).group(1))
wh = int(re.search(r"x(\d+)", geo).group(1))

with mss.mss() as sct:
    img = np.array(sct.grab({"left":wx,"top":wy,"width":ww,"height":wh}))

vis = cv2.cvtColor(img, cv2.COLOR_RGBA2BGR)
cv2.line(vis, (4, 0), (4, wh), (255, 0, 0), 3)
cv2.line(vis, (col3-wx, 0), (col3-wx, wh), (0, 0, 255), 3)

# 用 Pillow 绘制中文
pil_img = Image.fromarray(cv2.cvtColor(vis, cv2.COLOR_BGR2RGB))
draw = ImageDraw.Draw(pil_img)

# 找一个能用的中文字体
font_paths = [
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
]
font = None
for fp in font_paths:
    if os.path.exists(fp):
        font = ImageFont.truetype(fp, 24)
        break
if font is None:
    font = ImageFont.load_default()

draw.text((10, 35), "第一列 图标", fill=(255,0,0), font=font)
draw.text((30, 65), "第二列 列表+时间", fill=(0,255,0), font=font)
draw.text((col3-wx+15, 35), "第三列 内容", fill=(0,0,255), font=font)

info = f"窗口 {ww}x{wh} | 第三列 {col3-wx}px ({(col3-wx)/ww*100:.0f}%)"
draw.text((10, wh-30), info, fill=(255,255,255), font=font)

vis = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
out = os.path.expanduser("~/wechat_3cols_test.png")
cv2.imwrite(out, vis)
print(f"标记图: {out}")
print(f"第三列: {col3-wx}px, {(col3-wx)/ww*100:.0f}%")
