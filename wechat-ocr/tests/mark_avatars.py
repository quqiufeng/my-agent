#!/usr/bin/env python3
import cv2, json, os, numpy as np
from PIL import Image, ImageDraw, ImageFont
with open("/tmp/av_g.json") as f: data = json.load(f)
img = cv2.imread("/tmp/av_g.png")
pil_img = Image.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
draw = ImageDraw.Draw(pil_img)
font = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc", 14)
for i, a in enumerate(data["avatars"]):
    draw.rectangle([(a["x"],a["y"]),(a["x"]+a["w"],a["y"]+a["h"])], outline=(0,255,0), width=2)
    draw.text((a["x"]+a["w"]+5, a["y"]+5), a["text"], fill=(0,255,0), font=font)
out = os.path.expanduser("~/wechat_avatars_marked.png")
cv2.imwrite(out, cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR))
print(f"头像: {len(data['avatars'])}")
