# matmul.static.py — StaticPy: OpenBLAS 矩阵乘法
# 编译: bash static_build.sh matmul.static.py matmul
# 运行: scheme --quiet /tmp/static-build-*/matmul.so

extern fn cblas_dgemm(Order: int, TransA: int, TransB: int, M: int, N: int, K: int, alpha: float, A: list[float], lda: int, B: list[float], ldb: int, beta: float, C: list[float], ldc: int) -> void from "openblas"

extern fn cblas_ddot(n: int, x: list[float], incx: int, y: list[float], incy: int) -> float from "openblas"

def dot_product(a: list[float], b: list[float], n: int) -> float:
    return cblas_ddot(n, a, 1, b, 1)

def main():
    # 创建 3 个元素的数组 (在 Scheme prelude 中用 foreign-alloc)
    # 由于 foreign-alloc 在 Scheme 侧，这里只做计算演示
    
    # 简单浮点运算
    a: float = 3.14
    b: float = 2.71
    result: float = a * b + 1.0
    print(result)
    
    # 调用 extern FFI 函数
    x: float = cblas_ddot(0, 0, 0, 0, 0)
    print(x)
