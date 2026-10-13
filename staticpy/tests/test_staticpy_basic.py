def main():
    a: int = 1
    b: int = 2
    c: int = a + b
    print(c)
    if c == 3:
        print("INT OK")
    else:
        print("INT FAIL")
    
    x: float = 1.5
    y: float = 2.5
    z: float = x + y
    print(z)
    if z == 4.0:
        print("FLOAT OK")
    else:
        print("FLOAT FAIL")
    
    i: int = 0
    while i < 5:
        i = i + 1
    print(i)
    if i == 5:
        print("LOOP OK")
    else:
        print("LOOP FAIL")
