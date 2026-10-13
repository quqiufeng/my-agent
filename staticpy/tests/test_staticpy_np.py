import np

def main():
    a = np.array([1.0, 2.0, 3.0, 4.0])
    m = np.mean(a)
    print(m)
    if m == 2.5:
        print("NP MEAN OK")
    else:
        print("NP MEAN FAIL")
