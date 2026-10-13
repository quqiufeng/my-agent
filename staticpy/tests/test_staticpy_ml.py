import np
from torch import tensor, add

def main():
    # NumPy 风格
    a = np.array([1.0, 2.0, 3.0])
    b = np.array([4.0, 5.0, 6.0])
    s = np.dot(a, b)
    m = np.mean(a)
    print(s)
    print(m)

    # PyTorch 风格（需要运行时 libtorch_cpu.so 才实际执行）
    # t = tensor([1.0, 2.0])
    # r = add(t, t)

    if s == 32.0 and m == 2.0:
        print("ML STYLE OK")
    else:
        print("ML STYLE FAIL")
