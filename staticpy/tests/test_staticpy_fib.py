def fib(n: int) -> int:
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

def main():
    r: int = fib(10)
    print(r)
    if r == 55:
        print("FIB OK")
    else:
        print("FIB FAIL")
