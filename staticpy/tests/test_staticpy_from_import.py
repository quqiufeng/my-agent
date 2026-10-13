from np import array, dot, mean

def main():
    a = array([1.0, 2.0, 3.0])
    b = array([4.0, 5.0, 6.0])
    s = dot(a, b)
    print(s)
    m = mean(a)
    print(m)
    if s == 32.0 and m == 2.0:
        print("FROM IMPORT OK")
    else:
        print("FROM IMPORT FAIL")
