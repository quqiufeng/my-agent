# 测试闭包/高阶函数

from typing import Callable

def make_adder(n: int) -> Callable[[int], int]:
    def adder(x: int) -> int:
        return x + n
    return adder

def apply_twice(f: Callable[[int], int], x: int) -> int:
    return f(f(x))

def main():
    add5 = make_adder(5)
    r1 = add5(10)
    print(r1)

    r2 = apply_twice(add5, 3)
    print(r2)

    if r1 == 15 and r2 == 13:
        print("CLOSURE OK")
    else:
        print("CLOSURE FAIL")
