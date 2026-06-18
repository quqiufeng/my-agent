#!/usr/bin/env python3
"""检测微信第二列的红色未读标记"""
import cv2, numpy as np, subprocess, re, mss, sys

geo = subprocess.run(["xdotool","getactivewindow","getwindowgeometry"],capture_output=True,text=True).stdout
wx = int(re.search(r"Position: (\d+)", geo).group(1))
wy = int(re.search(r",(\d+)", geo).group(1))
ww = int(re.search(r"Geometry: (\d+)", geo).group(1))
wh = int(re.search(r"x(\d+)", geo).group(1))

col3 = int(sys.argv[1]) if len(sys.argv) > 1 else wx + int(ww * 0.40)

with mss.mss() as sct:
    img = np.array(sct.grab({"left":wx+4,"top":wy+50,"width":col3-wx-4,"height":wh-100}))

hsv = cv2.cvtColor(img, cv2.COLOR_RGBA2HSV)

# 红色HSV范围
lower1 = np.array([0, 80, 80])
upper1 = np.array([10, 255, 255])
lower2 = np.array([170, 80, 80])
upper2 = np.array([180, 255, 255])

mask = cv2.bitwise_or(cv2.inRange(hsv, lower1, upper1), cv2.inRange(hsv, lower2, upper2))
kernel = np.ones((3,3), np.uint8)
mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)

contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

spots = []
for c in contours:
    x, y, w, h = cv2.boundingRect(c)
    area = w * h
    ratio = w / h if h > 0 else 0
    if 30 < area < 3000 and 0.3 < ratio < 3.0 and h > 6:
        spots.append((wx+4+x, wy+50+y, w, h))

print(len(spots))
for sx, sy, w, h in spots:
    print(f"{sx} {sy} {w} {h}")
