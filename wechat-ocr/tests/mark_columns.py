#!/usr/bin/env python3
"""WeChat OCR - 三列结构标记图生成
用法: python3 mark_columns.py <第三列起始X坐标>
功能: 截图微信窗口 → 标注三列分界 → 保存到 ~/wechat_3cols_test.png
"""
import cv2, numpy as np, subprocess, re, mss, os, sys

# 获取第三列坐标
col3 = int(sys.argv[1]) if len(sys.argv) > 1 else 0

# 截图
geo = subprocess.run(["xdotool","getactivewindow","getwindowgeometry"],
                     capture_output=True,text=True).stdout
wx = int(re.search(r"Position: (\d+)", geo).group(1))
wy = int(re.search(r",(\d+)", geo).group(1))
ww = int(re.search(r"Geometry: (\d+)", geo).group(1))
wh = int(re.search(r"x(\d+)", geo).group(1))

with mss.mss() as sct:
    img = np.array(sct.grab({"left":wx,"top":wy,"width":ww,"height":wh}))

vis = cv2.cvtColor(img, cv2.COLOR_RGBA2BGR)

# 三列
cv2.line(vis, (4, 0), (4, wh), (255, 0, 0), 3)
cv2.line(vis, (col3-wx, 0), (col3-wx, wh), (0, 0, 255), 3)

cv2.putText(vis, "第一列 图标", (10, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255,0,0), 2)
cv2.putText(vis, "第二列 列表+时间", (20, 70), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0,255,0), 2)
cv2.putText(vis, "第三列 内容", (col3-wx+15, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0,0,255), 2)

info = f"窗口 {ww}x{wh} | 第三列 {col3-wx}px ({(col3-wx)/ww*100:.0f}%)"
cv2.putText(vis, info, (10, wh-20), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255,255,255), 2)

out = os.path.expanduser("~/wechat_3cols_test.png")
cv2.imwrite(out, vis)
print(f"标记图: {out}")
print(f"第三列: {col3-wx}px, {(col3-wx)/ww*100:.0f}%")
