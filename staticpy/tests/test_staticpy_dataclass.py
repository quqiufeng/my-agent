class Point:
    x: float
    y: float

class Color(Enum):
    RED = 0
    GREEN = 1
    BLUE = 2

def safe_div(a: float, b: float) -> result[float, str]:
    if b == 0.0:
        return Error("divide by zero")
    return Ok(a / b)

def main():
    p: Point = Point(1.0, 2.0)
    print(p.x)
    print(p.y)
    print(Color_GREEN)
    r = safe_div(10.0, 2.0)
    if is_ok(r):
        print(unwrap(r))
    else:
        print(0.0)
    bad = safe_div(5.0, 0.0)
    if is_error(bad):
        print("ERROR")
    else:
        print("OK")
    print("DATACLASS OK")
