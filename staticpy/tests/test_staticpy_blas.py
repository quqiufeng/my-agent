import np

def main():
    a = np.array([1.0, 2.0, 3.0])
    b = np.array([4.0, 5.0, 6.0])
    s = np.dot(a, b)
    print(s)
    if s == 32.0:
        print("NP ARRAY OK")
    else:
        print("NP ARRAY FAIL")
