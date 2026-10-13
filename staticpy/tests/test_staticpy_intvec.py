def main():
    n: int = 5
    arr: list[int] = make_int_array(n)
    
    i: int = 0
    while i < n:
        int_array_set(arr, i, i * 2)
        i = i + 1
    
    s: int = 0
    i = 0
    while i < n:
        s = s + int_array_ref(arr, i)
        i = i + 1
    
    print(s)
    if s == 20:
        print("INT VECTOR OK")
    else:
        print("INT VECTOR FAIL")
