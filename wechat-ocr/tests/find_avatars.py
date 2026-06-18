#!/usr/bin/env python3
"""检测微信第二列的头像"""
import cv2, numpy as np, subprocess, re, mss, os, sys

geo = subprocess.run(["xdotool","getactivewindow","getwindowgeometry"],capture_output=True,text=True).stdout
wx = int(re.search(r"Position: (\d+)", geo).group(1))
wy = int(re.search(r",(\d+)", geo).group(1))
ww = int(re.search(r"Geometry: (\d+)", geo).group(1))
wh = int(re.search(r"x(\d+)", geo).group(1))

with mss.mss() as sct:
    img = np.array(sct.grab({"left":wx,"top":wy,"width":ww,"height":wh}))

gray = cv2.cvtColor(img, cv2.COLOR_RGBA2GRAY)
col2 = gray[:, :int(ww*0.30)]

blur = cv2.GaussianBlur(col2, (3,3), 0)
edges = cv2.Canny(blur, 30, 100)
contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

avatars = []
for c in contours:
    x, y, w, h = cv2.boundingRect(c)
    area = w * h; ratio = w/h if h>0 else 0
    if 800 < area < 5000 and 0.7 < ratio < 1.5 and h > 25:
        avatars.append((wx+x, wy+y, w, h))

unique = []
for ax, ay, aw, ah in avatars:
    dup = False
    for ux, uy, uw, uh in unique:
        if abs(ax-ux) < 15 and abs(ay-uy) < 15: dup = True; break
    if not dup: unique.append((ax, ay, aw, ah))
unique.sort(key=lambda a: a[1])

vis = cv2.cvtColor(img, cv2.COLOR_RGBA2BGR)
for i, (ax, ay, aw, ah) in enumerate(unique):
    cv2.rectangle(vis, (ax-wx, ay-wy), (ax-wx+aw, ay-wy+ah), (0,255,0), 2)
    cv2.putText(vis, str(i+1), (ax-wx, ay-wy-5), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0,255,0), 2)

out = os.path.expanduser("~/wechat_avatars.png")
cv2.imwrite(out, vis)
print(len(unique))
