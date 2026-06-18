#!/usr/bin/env python3
"""标注头像检测结果"""
import cv2, json, os, numpy as np
from PIL import Image, ImageDraw, ImageFont

with open("/tmp/av_data.json") as f:
    data = json.load(f)

img = cv2.imread("/tmp/av_full.png")
pil_img = Image.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
draw = ImageDraw.Draw(pil_img)
font = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc", 14)

for i, a in enumerate(data["avatars"]):
    rx, ry = int(a["x"]), int(a["y"])
    rw, rh = int(a["w"]), int(a["h"])
    draw.rectangle([(rx,ry),(rx+rw,ry+rh)], outline=(0,255,0), width=2)
    draw.text((rx+rw+5, ry+5), f"#{i+1} {a['text'][:10]}", fill=(0,255,0), font=font)

out = os.path.expanduser("~/wechat_avatars_marked.png")
cv2.imwrite(out, cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR))
print(f"标注图: {out}\n头像: {len(data['avatars'])} 个")
