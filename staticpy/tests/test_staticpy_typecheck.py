#!/usr/bin/env python3
"""StaticPy 类型系统单元测试
直接调用 static_translate.typecheck_module，不经过完整编译流程。
"""
import sys
import ast
import importlib.util

spec = importlib.util.spec_from_file_location("static_translate", "/opt/ReScheme/static_translate.py")
st = importlib.util.module_from_spec(spec)
spec.loader.exec_module(st)


def reset_globals():
    st.TYPE_ENV = {}
    st.EXTERN_FUNCTIONS = {}
    st.IMPORTED_NAMES = {}
    st.MODULE_ALIASES = {}
    st.RECORD_TYPES = {}
    st.RECORD_FIELDS = {}
    st.FUNCTION_SIGS = {}


def typecheck(src):
    reset_globals()
    code = st.parse_extern_functions(src)
    tree = ast.parse(code)
    st.parse_imports(tree)
    st.collect_record_types(tree)
    try:
        st.typecheck_module(tree)
        return None
    except SystemExit:
        # typecheck_error 写入 stderr 并 exit(1)
        # 这里通过 monkey-patch 捕获消息
        return "error"


def typecheck_capturing(src):
    """返回类型错误消息或 None"""
    reset_globals()
    code = st.parse_extern_functions(src)
    tree = ast.parse(code)
    st.parse_imports(tree)
    st.collect_record_types(tree)

    captured = []
    orig = st.typecheck_error
    def capture(node, msg):
        captured.append(msg)
    st.typecheck_error = capture
    try:
        st.typecheck_module(tree)
    except SystemExit:
        pass
    st.typecheck_error = orig
    return captured[0] if captured else None


def expect_ok(src):
    msg = typecheck_capturing(src)
    if msg:
        print(f"FAIL: expected OK but got error: {msg}")
        return False
    print(f"OK: {src.splitlines()[0]}")
    return True


def expect_error(src, substring):
    msg = typecheck_capturing(src)
    if msg is None:
        print(f"FAIL: expected error containing '{substring}' but got OK")
        return False
    if substring not in msg:
        print(f"FAIL: expected error containing '{substring}', got: {msg}")
        return False
    print(f"OK caught: {msg}")
    return True


def main():
    tests = []

    # 合法程序
    tests.append(expect_ok("""
def main():
    a: int = 1
    b: float = a
    print(b)
"""))

    tests.append(expect_ok("""
def add(x: int, y: int) -> int:
    return x + y

def main():
    print(add(1, 2))
"""))

    tests.append(expect_ok("""
def safe_div(a: float, b: float) -> result[float, str]:
    if b == 0.0:
        return Error("zero")
    return Ok(a / b)

def main():
    print(safe_div(1.0, 2.0))
"""))

    # 非法：str 赋值给 int
    tests.append(expect_error("""
def main():
    a: int = "hello"
    print(a)
""", "cannot assign"))

    # 非法：返回值类型不匹配
    tests.append(expect_error("""
def f() -> int:
    return "hello"

def main():
    print(f())
""", "return value"))

    # 非法：参数类型不匹配
    tests.append(expect_error("""
def add(x: int, y: int) -> int:
    return x + y

def main():
    print(add(1, "two"))
""", "argument 2"))

    # 非法：未定义变量
    tests.append(expect_error("""
def main():
    print(x)
""", "undefined name 'x'"))

    # 非法：下标非 int
    tests.append(expect_error("""
def main():
    a: list[int] = [1, 2, 3]
    print(a["x"])
""", "index must be int"))

    # 非法：记录字段不存在
    tests.append(expect_error("""
class Point:
    x: float
    y: float

def main():
    p: Point = Point(1.0, 2.0)
    print(p.z)
""", "has no field 'z'"))

    # Any 类型：可以赋值任意值，也可以被赋任意值
    tests.append(expect_ok("""
def main():
    a: Any = 1
    a = "hello"
    a = [1.0, 2.0]
"""))

    # 未标注变量推断为 Any，后续赋值不报错
    tests.append(expect_ok("""
def main():
    b = 10
    b = "string"
    b = 3.14
"""))

    # 列表拼接类型检查
    tests.append(expect_ok("""
def main():
    a: list[float] = [1.0, 2.0]
    b: list[float] = [3.0, 4.0]
    c = a + b
    print(c[0])
"""))

    # for ... in list 元素类型推断
    tests.append(expect_ok("""
def main():
    arr: list[float] = [1.0, 2.0, 3.0]
    total: float = 0.0
    for v in arr:
        total = total + v
"""))

    if all(tests):
        print("\nAll typecheck tests passed.")
        return 0
    else:
        print(f"\n{len([t for t in tests if not t])} typecheck test(s) failed.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
