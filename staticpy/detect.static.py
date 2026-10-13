# detect.static.py — YOLO 检测（StaticPy，纯原生，无 Python）
# 编译: cd /opt/my-agent/staticpy && bash static_build.sh detect.static.py detect
import torch


def main():
    m = torch.jit_load("/tmp/yolov8n.torchscript")
    img = torch.load_image("/tmp/frame.ppm")                   # (C,H,W) uint8
    img = torch.image_resize_float(img, 640, 640, "bilinear")
    x = torch.unsqueeze(img, 0)                                # (1,C,640,640)
    out = torch.jit_forward(m, x)                              # (1,84,8400)
    print("NUMEL")
    print(torch.numel(out))
