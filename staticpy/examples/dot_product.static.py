# StaticPy 数值计算示例
# 数组类型 list[float] = C double*（用 prelude 函数管理）

extern fn make_float_array(n: int) -> list[float] from "prelude"
extern fn float_array_set(ptr: list[float], i: int, val: float) -> void from "prelude"
extern fn float_array_ref(ptr: list[float], i: int) -> float from "prelude"
extern fn cblas_ddot(n: int, x: list[float], incx: int, y: list[float], incy: int) -> float from "openblas"

def dot_product(a: list[float], b: list[float], n: int) -> float:
    return cblas_ddot(n, a, 1, b, 1)

def main():
    n: int = 3
    a: list[float] = make_float_array(n)
    b: list[float] = make_float_array(n)
    float_array_set(a, 0, 1.0)
    float_array_set(a, 1, 2.0)
    float_array_set(a, 2, 3.0)
    float_array_set(b, 0, 4.0)
    float_array_set(b, 1, 5.0)
    float_array_set(b, 2, 6.0)
    result: float = dot_product(a, b, n)
    print(result)
